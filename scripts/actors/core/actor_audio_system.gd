class_name ActorAudioSystem
extends Node
## Timeline transport owns playback, including seeking, mixing and pitch compensation.
var players: Dictionary = {}
var envelopes: Dictionary = {}
var jobs: Dictionary = {}
var _scrub_remaining: Dictionary = {}
var output_bus := "Master"

func set_output_bus(value: String) -> void:
	output_bus = value if AudioServer.get_bus_index(value) >= 0 else "Master"
	for player: AudioStreamPlayer in players.values():
		var bus := AudioServer.get_bus_index(player.bus)
		if bus >= 0: AudioServer.set_bus_send(bus, output_bus)

## Short forward grains preview the source under the cursor, even when scrubbing backwards.
## Each grain expires independently, so paused transport never leaves audio running.
func scrub(model: ActorTimeline, time: float) -> void:
	synchronize(model, time, true)
	for clip in model.clips:
		if not players.has(clip.id): continue
		var player: AudioStreamPlayer = players[clip.id]
		if not player.playing: continue
		player.seek(clip.local_time(time))
		_scrub_remaining[clip.id] = minf(0.12, clip.start_time + clip.duration - time)

func _process(delta: float) -> void:
	for id in _scrub_remaining.keys():
		_scrub_remaining[id] -= delta
		if _scrub_remaining[id] <= 0.0:
			if players.has(id): players[id].stop()
			_scrub_remaining.erase(id)

func synchronize(model: ActorTimeline, time: float, playing: bool) -> void:
	_scrub_remaining.clear()
	var live: Dictionary = {}
	for index in model.clips.size():
		var actor := model.actors[index]
		if actor.type_id != &"audio": continue
		var clip := model.clips[index]
		live[clip.id] = true
		var stream := ActorAudio.source(actor.values.get(&"audio", ""))
		if stream == null:
			if players.has(clip.id): _remove_player(clip.id)
			continue
		if not players.has(clip.id):
			var player := AudioStreamPlayer.new()
			var bus := "ActorAudio_%s_%s" % [get_instance_id(), clip.id]
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.add_bus_effect(AudioServer.bus_count - 1, AudioEffectPitchShift.new())
			AudioServer.set_bus_send(AudioServer.bus_count - 1, output_bus)
			player.bus = bus
			add_child(player)
			players[clip.id] = player
		var player: AudioStreamPlayer = players[clip.id]
		if player.stream != stream:
			player.stop()
			player.stream = stream
		player.pitch_scale = clip.playback_speed
		player.volume_db = float(actor.get_value(&"volume_db", 0.0)) + linear_to_db(maxf(0.00001, ActorAudio.fade_gain(actor, clip, time)))
		var effect := AudioServer.get_bus_effect(AudioServer.get_bus_index(player.bus), 0) as AudioEffectPitchShift
		effect.pitch_scale = clampf(float(actor.get_value(&"pitch", 1.0)) / clip.playback_speed, 0.01, 16.0)
		if not playing or not clip.contains_time(time) or actor.get_value(&"muted", false):
			player.stop()
		elif not player.playing:
			player.play(clip.local_time(time))
		elif absf(player.get_playback_position() - clip.local_time(time)) > 0.15:
			player.seek(clip.local_time(time))
	for id in players.keys():
		if not live.has(id): _remove_player(id)

func _remove_player(id: String) -> void:
	_scrub_remaining.erase(id)
	var player: AudioStreamPlayer = players[id]
	player.stop()
	var bus := AudioServer.get_bus_index(player.bus)
	if bus > 0: AudioServer.remove_bus(bus)
	player.queue_free()
	players.erase(id)

func waveform(stream: AudioStream) -> PackedFloat32Array:
	if stream == null: return PackedFloat32Array()
	var id := stream.get_instance_id()
	if envelopes.has(id): return envelopes[id]
	if not jobs.has(id):
		var thread := Thread.new()
		thread.start(_decode.bind(stream))
		jobs[id] = thread
	var thread: Thread = jobs[id]
	if thread.is_alive(): return PackedFloat32Array()
	envelopes[id] = thread.wait_to_finish()
	jobs.erase(id)
	return envelopes[id]

static func _decode(stream: AudioStream) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(4096)
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var total := maxi(1, int(stream.get_length() * AudioServer.get_mix_rate()))
	var cursor := 0
	while cursor < total:
		var samples := playback.mix_audio(1.0, mini(4096, total - cursor))
		if samples.is_empty(): break
		for sample in samples:
			var bin := mini(4095, int(float(cursor) / total * 4096.0))
			result[bin] = maxf(result[bin], maxf(absf(sample.x), absf(sample.y)))
			cursor += 1
	playback.stop()
	return result

func _exit_tree() -> void:
	for id in players.keys(): _remove_player(id)
	for thread: Thread in jobs.values(): thread.wait_to_finish()
	jobs.clear()
