class_name ActorAudioSystem
extends Node
## Timeline transport owns playback, including seeking, mixing and pitch compensation.
var players: Dictionary = {}
var envelopes: Dictionary = {}
var jobs: Dictionary = {}
var _scrub_remaining: Dictionary = {}
var output_bus := "Master"
# Optional workspace routing. Existing scene actors retain unchanged defaults.
var clip_output_buses: Dictionary = {}
var clip_effects: Dictionary = {}
var clip_pan: Dictionary = {}
var clip_stream_overrides: Dictionary = {}
var _effect_signatures: Dictionary = {}
const WorkspaceEffects = preload("res://Workspaces/AudioWorkspace/audio_effects.gd")

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
	for index in mini(model.clips.size(), model.actors.size()):
		var actor := model.actors[index]
		if actor.type_id != &"audio": continue
		var clip := model.clips[index]
		live[clip.id] = true
		var stream: AudioStream = clip_stream_overrides[clip.id] if clip_stream_overrides.has(clip.id) else ActorAudio.source(actor.values.get(&"audio", ""))
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
		var bus_index := AudioServer.get_bus_index(player.bus)
		var destination := str(clip_output_buses.get(clip.id, output_bus))
		AudioServer.set_bus_send(bus_index, destination if AudioServer.get_bus_index(destination) >= 0 else output_bus)
		var stack: Array = clip_effects.get(clip.id, [])
		var pan_value := float(clip_pan.get(clip.id, actor.get_value(&"pan", 0.0)))
		var signature := var_to_str(stack)
		if str(_effect_signatures.get(clip.id, "")) != signature:
			var native_stack: Array[AudioEffect] = []
			for entry in stack:
				var native_effect := WorkspaceEffects.native(entry)
				if native_effect != null: native_stack.append(native_effect)
			var same_types := AudioServer.get_bus_effect_count(bus_index) == native_stack.size() + 2
			if same_types:
				for effect_index in native_stack.size():
					if AudioServer.get_bus_effect(bus_index,effect_index+1).get_class()!=native_stack[effect_index].get_class(): same_types=false; break
			if same_types:
				for effect_index in native_stack.size(): WorkspaceEffects.update_native_properties(AudioServer.get_bus_effect(bus_index,effect_index+1),native_stack[effect_index])
			else:
				while AudioServer.get_bus_effect_count(bus_index) > 1: AudioServer.remove_bus_effect(bus_index,1)
				for native_effect in native_stack: AudioServer.add_bus_effect(bus_index,native_effect)
				AudioServer.add_bus_effect(bus_index,AudioEffectPanner.new())
			_effect_signatures[clip.id] = signature
		var panner := AudioServer.get_bus_effect(bus_index,AudioServer.get_bus_effect_count(bus_index)-1) as AudioEffectPanner
		if panner != null: panner.pan=clampf(pan_value,-1,1)
		player.pitch_scale = clip.playback_speed
		player.volume_db = float(actor.get_value(&"volume_db", 0.0)) + linear_to_db(maxf(0.00001, ActorAudio.fade_gain(actor, clip, time)))
		var effect := AudioServer.get_bus_effect(AudioServer.get_bus_index(player.bus), 0) as AudioEffectPitchShift
		effect.pitch_scale = clampf(float(actor.get_value(&"pitch", 1.0)) / clip.playback_speed, 0.01, 16.0)
		if not playing or not clip.contains_time(time) or actor.get_value(&"muted", false):
			player.stop()
		else:
			var source_time := clip.local_time(time)
			if bool(actor.values.get(&"loop", false)) and stream.get_length() > 0:
				source_time = fposmod(source_time, stream.get_length())
			if not player.playing: player.play(source_time)
			elif absf(player.get_playback_position() - source_time) > 0.15: player.seek(source_time)
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
	_effect_signatures.erase(id)

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
