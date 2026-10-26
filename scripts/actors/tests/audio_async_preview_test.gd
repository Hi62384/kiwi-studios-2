extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1; push_error(message)

func _initialize() -> void: run.call_deferred()

func await_queue(reader: KiwiAudioFilePreview.Reader, count: int) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		var state := reader.status()
		if not str(state.error).is_empty(): return false
		if int(state.queued) >= count: return true
		await process_frame
	return false

func await_prime(preview: KiwiAudioFilePreview) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while preview.active and preview._priming and Time.get_ticks_msec() < deadline: await process_frame

func run() -> void:
	var directory := "user://async_pcm_" + ActorData.new_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("source.wav")
	# Distinct halves make stale generation delivery observable, not just a
	# reflection of an internal cursor. The fixture remains under 1 MiB.
	var samples := PackedVector2Array(); samples.resize(44100 * 4)
	for i in samples.size(): samples[i] = Vector2(0.125, -0.25) if i < 88200 else Vector2(-0.5, 0.75)
	var source := KiwiAudioSourceCache.to_wav(samples)
	check(source.save_to_wav(path) == OK, "PCM fixture writes")
	var info := KiwiAudioPCMFile.inspect(path)
	var reader := KiwiAudioFilePreview.Reader.new(); reader.path = path; reader.info = info
	var generation := reader.seek_to(0, false)
	var thread := Thread.new()
	check(thread.start(reader.run) == OK, "Dedicated PCM reader starts")
	check(await await_queue(reader, KiwiAudioFilePreview.QUEUE_CHUNKS), "Read-ahead fills its bounded queue")
	await create_timer(0.03).timeout
	check(int(reader.status().queued) == KiwiAudioFilePreview.QUEUE_CHUNKS, "Read-ahead stops at 32 chunks")
	var packet := reader.take(KiwiAudioFilePreview.CHUNK_FRAMES)
	var pcm: PackedVector2Array = packet.get("samples", PackedVector2Array())
	check(int(packet.get("generation", -1)) == generation and not pcm.is_empty() and absf(pcm[0].x - 0.125) < 0.001, "Initial queue contains the original source samples")
	# A pending read may race this seek; every exposed packet must be new.
	generation = reader.seek_to(100000, false)
	check(await await_queue(reader, 1), "Reader prepares a new seek generation")
	packet = reader.take(KiwiAudioFilePreview.CHUNK_FRAMES); pcm = packet.get("samples", PackedVector2Array())
	check(int(packet.get("generation", -1)) == generation and not pcm.is_empty() and absf(pcm[0].x + 0.5) < 0.001, "Seek discards old PCM and delivers the requested half")
	generation = reader.seek_to(samples.size() - 7, false)
	check(await await_queue(reader, 1), "Reader reaches a short tail")
	packet = reader.take(KiwiAudioFilePreview.CHUNK_FRAMES); pcm = packet.get("samples", PackedVector2Array())
	check(pcm.size() == 7 and bool(packet.get("final", false)), "Final packet stops at the declared frame boundary")
	generation = reader.seek_to(samples.size() - 7, true)
	check(await await_queue(reader, 2), "Loop queues the tail and source start")
	var tail := reader.take(KiwiAudioFilePreview.CHUNK_FRAMES)
	packet = reader.take(KiwiAudioFilePreview.CHUNK_FRAMES); pcm = packet.get("samples", PackedVector2Array())
	check(not bool(tail.get("final", true)) and not pcm.is_empty() and absf(pcm[0].x - 0.125) < 0.001, "Loop crosses the source boundary without stale tail repetition")
	reader.cancel(); thread.wait_to_finish()
	check(reader.status().queued == 0, "Cancellation clears queued PCM and joins the owned reader")
	var preview := KiwiAudioFilePreview.new(); root.add_child(preview)
	var releases: Array[String] = []
	var errors: Array[String] = []
	preview.released.connect(func(value: String): releases.append(value))
	preview.failed.connect(func(value: String): errors.append(value))
	check(preview.open_file(path, "Master", info, true).is_empty(), "File preview accepts a valid prepared source")
	await await_prime(preview)
	check(preview.active and not preview._priming, "File preview primes asynchronously")
	preview.seek_file(3.0); preview.seek_file(0.25); preview.seek_file(2.25)
	await await_prime(preview)
	check(preview.active and absf(preview.position_seconds() - 2.25) < 0.3, "Rapid seeks use only the final requested position")
	preview.close_file()
	var deadline := Time.get_ticks_msec() + 5000
	while not preview._readers.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(releases == [path] and preview._readers.is_empty(), "Owned source releases exactly once after the reader closes")
	check(errors.is_empty(), "Normal queued playback emits no failure")
	var stale := info.duplicate(); stale.file_bytes = int(info.file_bytes) + 1
	preview.open_file(path, "Master", stale)
	deadline = Time.get_ticks_msec() + 5000
	while preview.active and Time.get_ticks_msec() < deadline: await process_frame
	check(not preview.active and not errors.is_empty() and errors.back().contains("changed"), "Changed prepared source fails visibly on the worker")
	preview.queue_free(); await process_frame
	check(DirAccess.remove_absolute(path) == OK, "Teardown leaves no reader holding the file")
	DirAccess.remove_absolute(directory)
	print("AUDIO_ASYNC_PREVIEW checks=%d failures=%d" % [checks, failures])
	quit(failures)
