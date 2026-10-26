extends SceneTree
const Writer = preload("res://scripts/actors/core/audio_take_writer.gd")
const Finalize = preload("res://Workspaces/AudioWorkspace/audio_take_finalize.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	var directory := ProjectSettings.globalize_path(Finalize.ROOT + "/" + ActorData.new_id())
	if DirAccess.make_dir_recursive_absolute(directory) != OK: push_error("Could not create isolated take fixture."); quit(1); return
	var writer := Writer.new()
	check(writer.start(directory.path_join("microphone.wav"), 48000, false).is_empty(), "Disk writer starts")
	var block := PackedVector2Array(); block.resize(4096)
	for index in block.size(): block[index] = Vector2(.25, -.5)
	for index in 24:
		writer.append_frames(block); await process_frame
	writer.request_finish()
	while writer.busy(): await process_frame
	var result := writer.finish()
	check(str(result.error).is_empty(), "Disk writer completes without errors")
	var info := KiwiAudioPCMFile.inspect(result.path)
	check(int(info.get("frames",0)) == 24 * 4096, "Finalized WAV header preserves every accepted frame")
	check(int(info.get("align",0)) == 4 and int(info.get("rate",0)) == 48000, "Disk take retains rate and stereo geometry")
	var input := FileAccess.open(result.path,FileAccess.READ)
	var samples := KiwiAudioPCMFile.read_frames(input, info, 100, 1); input.close()
	check(samples.size()==1 and samples[0].distance_to(Vector2(.25,-.5))<.0001, "PCM data is captured with the expected amplitudes")
	var capture := {"directory":directory,"paths":[result.path],"mono":false,"error":""}
	var single := Finalize.finalize(capture)
	check(single.path == result.path, "A dry take reuses its disk source without a whole-take decode")
	check(not Writer.new().start(result.path,48000,false).is_empty(), "Capture refuses to overwrite an existing source")
	var second := Writer.new(); check(second.start(directory.path_join("timeline.wav"),44100,true).is_empty(), "Second source supports a distinct rate and mono capture")
	second.append_frames(block); second.request_finish()
	while second.busy(): await process_frame
	var other := second.finish()
	if not ActorVideo.executable("ffmpeg").is_empty():
		capture.paths.append(other.path)
		# No audio device is opened. Finalizer uses the shared encoder backend.
		var thread := Thread.new(); thread.start(func(): return Finalize.finalize(capture))
		while thread.is_alive(): await process_frame
		var mixed: Dictionary = thread.wait_to_finish()
		check(str(mixed.error).is_empty() and not str(mixed.path).is_empty(), "Multi-source finalization streams through FFmpeg")
		check(FileAccess.file_exists(result.path) and FileAccess.file_exists(other.path), "Finalization preserves separate capture sources")
		var mixed_info:=KiwiAudioPCMFile.inspect(mixed.path);var reader:=FileAccess.open(mixed.path,FileAccess.READ)
		var mixed_frames:=KiwiAudioPCMFile.read_frames(reader,mixed_info,480,1);reader.close()
		check(mixed_frames.size()==1 and mixed_frames[0].distance_to(Vector2(.125,-.625))<.001,"Disk mix preserves summed amplitude across distinct source rates")
	var document := KiwiAudioDocument.from_source(result.path)
	var session := KiwiAudioEditSession.new(); session.document = document
	var count := document.clips.size()
	session.action("Insert disk take",func(): session.insert_source(result.path,2,document.tracks[0].id,"Disk take"))
	check(session.document.clips.size()==count+1, "File-backed takes insert into the existing document")
	session.undo(); check(session.document.clips.size()==count and FileAccess.file_exists(result.path), "Undo removes metadata without destroying the capture")
	check(Finalize.recoverable().any(func(entry: Dictionary): return str(entry.directory).replace("\\","/")==directory.replace("\\","/")), "Finalized take files are available to recovery")
	var legacy := ActorAudioRecorder.new(); check(not legacy.disk_backed,"Existing Scene recorder keeps its original API by default"); legacy.free()
	var capture_directory:=ProjectSettings.globalize_path(Finalize.ROOT+"/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(capture_directory)
	var disk:=ActorAudioRecorder.new();disk.disk_backed=true;root.add_child(disk)
	disk._take_directory=capture_directory;disk._mic_writer=Writer.new();disk._mic_writer.start(capture_directory.path_join("microphone.wav"),48000,false);disk._mic_writer.append_frames(block);disk.recording=true
	var stopped:Dictionary=await disk.stop_to_files()
	check(stopped.paths.size()==1 and str(stopped.error).is_empty(),"Recorder stop finalizes a synthetic disk take without an AudioStreamWAV return")
	check(disk._mic_writer==null and not disk.recording,"Disk stop releases writer ownership")
	disk.queue_free();await process_frame
	print("AUDIO_DISK_TAKE checks=%d failures=%d fixture=%s" % [checks,failures,directory])
	quit(failures)
