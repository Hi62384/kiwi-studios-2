class_name KiwiAudioPlayback
extends Node
signal position_changed(seconds: float)
signal state_changed
signal exact_requested(seconds:float)
signal preview_file_released(path: String)
signal preview_failed(message: String)
var system := ActorAudioSystem.new()
var document: KiwiAudioDocument
var model := ActorTimeline.new()
var position: float = 0.0
var playing := false
var metronome := false
var loop_enabled := false
var _bus_names: Array[String] = []
var _track_buses: Dictionary = {}
var _track_effects: Dictionary = {}
var _master := ""
var _click := AudioStreamPlayer.new()
var _last_beat := ""
var _conductor := KiwiAudioConductor.new()
var _external_output := "Master"
var _bus_signature := ""
var _runtime_sources: Array[ActorData] = []
var exact_preview := AudioStreamPlayer.new()
var exact_preview_active := false
var _exact_start := 0.0
var exact_required := false
var exact_pending := false
var _exact_bus := ""
var file_preview := KiwiAudioFilePreview.new()
var _file_length := 0.0

func _ready() -> void:
	add_child(system)
	add_child(_click)
	add_child(exact_preview)
	add_child(file_preview)
	file_preview.released.connect(func(path: String): preview_file_released.emit(path))
	file_preview.failed.connect(func(message: String): stop(false); preview_failed.emit(message))
	file_preview.finished.connect(func():
		position = _exact_start + _file_length
		exact_preview_active = false; playing = false
		position_changed.emit(position); state_changed.emit())
	_click.volume_db = -20
	var samples := PackedVector2Array()
	samples.resize(1000)
	for i in samples.size():
		var value := sin(TAU * 1400.0 * i / 44100.0) * exp(-float(i) / 150.0) * 0.4
		samples[i] = Vector2(value, value)
	_click.stream = KiwiAudioSourceCache.to_wav(samples)
	exact_preview.finished.connect(func():
		if playing and loop_enabled and document != null and document.loop_end > document.loop_start:
			exact_preview.play(); position = _exact_start; _last_beat = ""
		else: exact_preview_active = false; playing = false; state_changed.emit())

func set_document(value: KiwiAudioDocument) -> void:
	var was_playing := playing or exact_pending
	stop(false)
	document = value
	_conductor = value.conductor() if value != null else KiwiAudioConductor.new()
	_last_beat = ""
	model.actors.clear()
	model.clips.clear()
	_runtime_sources.clear()
	system.clip_stream_overrides.clear()
	if value == null: return
	for actor in value.actors:
		var copy := ActorData.new()
		copy.id = actor.id
		copy.type_id = &"audio"
		copy.display_name = actor.display_name
		copy.values = actor.values.duplicate(true)
		model.actors.append(copy)
		_runtime_sources.append(actor)
	model.clips.assign(value.clips)
	for i in mini(value.actors.size(), value.clips.size()):
		if ActorAudio.needs_file_preview(value.actors[i].values.get(&"audio")):
			# Keep the shared scene backend unchanged; this workspace renders large
			# path sources with FFmpeg and monitors their completed PCM from disk.
			system.clip_stream_overrides[value.clips[i].id] = null
	var topology: Array = []
	for track in document.tracks: topology.append([track.id,track.get("output","")])
	var signature := var_to_str(topology)
	if _master.is_empty() or signature != _bus_signature:
		_rebuild_buses()
		_bus_signature = signature
	if was_playing and exact_required:
		exact_pending = true
		exact_requested.emit(position)
	else: playing = was_playing
	synchronize()

func set_output_bus(destination: String) -> void:
	_external_output = destination if AudioServer.get_bus_index(destination) >= 0 else "Master"
	if not _master.is_empty(): AudioServer.set_bus_send(AudioServer.get_bus_index(_master), _external_output)
	if not _exact_bus.is_empty(): AudioServer.set_bus_send(AudioServer.get_bus_index(_exact_bus), _external_output)

func _new_bus(label: String, destination: String) -> String:
	var name := "KiwiAudio_%s_%s" % [get_instance_id(), label]
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, name)
	AudioServer.set_bus_send(index, destination)
	_bus_names.append(name)
	return name

func _rebuild_buses() -> void:
	_clear_buses()
	if document == null: return
	_exact_bus = _new_bus("Exact", _external_output)
	_master = _new_bus("Master", _external_output)
	var master_index := AudioServer.get_bus_index(_master)
	_install_effects(master_index, document.master.get("effects", []))
	var safety := AudioEffectHardLimiter.new()
	safety.ceiling_db = -0.3
	AudioServer.add_bus_effect(master_index, safety)
	# Destinations are always earlier buses. Cyclic routes are rejected by the document.
	var remaining := document.tracks.duplicate()
	var pass_count := 0
	while not remaining.is_empty() and pass_count <= document.tracks.size():
		pass_count += 1
		for track in remaining.duplicate():
			var output := str(track.get("output", ""))
			if not output.is_empty() and not _track_buses.has(output): continue
			var bus := _new_bus(str(track.id), str(_track_buses.get(output, _master)))
			_track_buses[track.id] = bus
			_install_effects(AudioServer.get_bus_index(bus), track.get("effects", []))
			var pan := AudioEffectPanner.new()
			pan.pan = float(track.get("pan", 0))
			AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), pan)
			remaining.erase(track)
	for track in remaining:
		_track_buses[track.id] = _new_bus(str(track.id), _master)
	system.set_output_bus(_master)
	_click.bus = _master

func _install_effects(bus: int, stack: Array) -> void:
	for state in stack:
		var effect := KiwiAudioEffects.native(state)
		if effect != null: AudioServer.add_bus_effect(bus, effect)

func _clear_buses() -> void:
	for id in system.players.keys(): system._remove_player(id)
	_track_buses.clear()
	_track_effects.clear()
	for name in _bus_names:
		var index := AudioServer.get_bus_index(name)
		if index > 0: AudioServer.remove_bus(index)
	_bus_names.clear()
	_master = ""
	_exact_bus = ""

func play() -> void:
	if document == null:return
	if playing or exact_pending:stop(false);return
	if position >= document.duration():position=document.loop_start if loop_enabled else 0
	if exact_required:
		exact_pending=true;exact_requested.emit(position);state_changed.emit();return
	playing=true;_last_beat="";synchronize();state_changed.emit()

func stop(reset: bool = true) -> void:
	playing = false
	file_preview.close_file()
	exact_preview.stop()
	exact_preview_active = false
	exact_pending = false
	exact_preview.stream = null
	_click.stop()
	if reset: position = 0
	system.synchronize(model, position, false)
	position_changed.emit(position)
	state_changed.emit()

func seek(seconds:float,scrub:bool=false)->void:
	_last_beat=""
	position=maxf(0,seconds)
	if exact_preview_active:
		var length:=_file_length if file_preview.active else (exact_preview.stream.get_length() if exact_preview.stream!=null else 0.0)
		if position>=_exact_start and position<_exact_start+length:
			if file_preview.active: file_preview.seek_file(position-_exact_start)
			else: exact_preview.seek(position-_exact_start)
		else:
			file_preview.close_file()
			exact_preview.stop();exact_preview_active=false;exact_pending=true;playing=false
			exact_requested.emit(position)
	elif exact_pending or (exact_required and playing):
		playing=false;exact_pending=true;exact_requested.emit(position)
	else:
		synchronize()
		if scrub and not playing and not exact_required:system.scrub(model,position)
	position_changed.emit(position)

func play_exact(stream: AudioStream, start: float) -> void:
	stop(false)
	_exact_start = start
	_last_beat = ""
	position = start
	exact_preview.stream = stream
	exact_preview.bus = _exact_bus if not _exact_bus.is_empty() else _external_output
	exact_preview.play()
	exact_preview_active = true
	playing = true
	state_changed.emit()

func play_file(path: String, start: float, info: Dictionary) -> String:
	stop(false)
	_exact_start = start; position = start; _last_beat = ""
	_file_length = float(info.get("duration", 0.0))
	file_preview.loop_enabled = loop_enabled
	var error := file_preview.open_file(path, _exact_bus if not _exact_bus.is_empty() else _external_output, info, true)
	if not error.is_empty(): return error
	exact_preview_active = true; exact_pending = false; playing = true
	synchronize(); state_changed.emit()
	return ""

func _process(delta: float) -> void:
	if not playing or document == null: return
	if exact_preview_active:
		if file_preview.active:
			file_preview.loop_enabled = loop_enabled
			position = _exact_start + file_preview.position_seconds()
		else: position = _exact_start + exact_preview.get_playback_position()
	else:
		position += delta
		if loop_enabled and document.loop_end > document.loop_start and position >= document.loop_end:
			position = document.loop_start + fposmod(position - document.loop_start, document.loop_end - document.loop_start)
			_last_beat = ""
		elif position >= document.duration() + 0.1:
			stop(false)
			return
		synchronize()
	# Both live playback and rendered exact preview use the project conductor.
	# The click remains a transport monitor and is not baked into exported audio.
	if metronome and _conductor.error.is_empty():
		var beat := _conductor.beat_info(_conductor.seconds_to_beat(position))
		if str(beat.key) != _last_beat:
			_click.pitch_scale = 1.3 if bool(beat.downbeat) else 1.0
			_click.play()
			_last_beat = str(beat.key)
	elif not metronome: _last_beat = ""
	position_changed.emit(position)

func musical_position(seconds: float) -> String:
	return _conductor.position_text(seconds)

func synchronize() -> void:
	if document == null or _master.is_empty(): return
	if exact_preview_active or exact_pending or (exact_required and playing):
		system.synchronize(model,position,false)
		return
	var any_solo := false
	for track in document.tracks:
		if bool(track.get("solo", false)): any_solo = true
	var master_db := KiwiAudioEditSession.automation_value(document.master.get("automation", {}).get("volume_db", []), position, float(document.master.get("volume_db", -3)))
	_update_effects(AudioServer.get_bus_index(_master),KiwiAudioEffects.evaluated_stack(document.master.get("effects",[]),position))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_master), master_db)
	for track in document.tracks:
		var index := AudioServer.get_bus_index(str(_track_buses.get(track.id, "")))
		if index < 0: continue
		_update_effects(index,KiwiAudioEffects.evaluated_stack(track.get("effects",[]),position))
		var db := KiwiAudioEditSession.automation_value(track.get("automation", {}).get("volume_db", []), position, float(track.get("volume_db", 0)))
		AudioServer.set_bus_volume_db(index, db)
		AudioServer.set_bus_mute(index, bool(track.get("mute", false)) or (any_solo and not bool(track.get("solo", false)) and str(track.get("kind", "")) != "group"))
		var count := AudioServer.get_bus_effect_count(index)
		if count > 0:
			var pan := AudioServer.get_bus_effect(index, count - 1) as AudioEffectPanner
			if pan != null: pan.pan = KiwiAudioEditSession.automation_value(track.get("automation", {}).get("pan", []), position, float(track.get("pan", 0)))
	for i in mini(model.actors.size(), _runtime_sources.size()):
		var source := _runtime_sources[i]
		var actor := model.actors[i]
		var clip := model.clips[i]
		var local := position - clip.start_time
		var automation: Dictionary = source.values.get(&"automation", {})
		actor.values[&"volume_db"] = KiwiAudioEditSession.automation_value(automation.get("volume_db", []), local, float(source.values.get(&"volume_db", 0)))
		actor.values[&"pitch"] = KiwiAudioEditSession.automation_value(automation.get("pitch", []), local, float(source.values.get(&"pitch", 1)))
		actor.values[&"muted"] = source.values.get(&"muted", false)
		for key in [&"fade_in",&"fade_out",&"fade_curve",&"loop"]: actor.values[key]=source.values.get(key,0.0 if key in [&"fade_in",&"fade_out"] else false)
		system.clip_pan[clip.id] = KiwiAudioEditSession.automation_value(automation.get("pan", []), local, float(source.values.get(&"pan", 0)))
		system.clip_output_buses[clip.id] = _track_buses.get(str(source.values.get(&"track_id", "")), _master)
		system.clip_effects[clip.id] = KiwiAudioEffects.evaluated_stack(source.values.get(&"effects", []),local)
	system.synchronize(model, position, playing)

func meter(track_id: String = "") -> Vector2:
	var bus := AudioServer.get_bus_index((_exact_bus if exact_preview_active else _master) if track_id.is_empty() else str(_track_buses.get(track_id, "")))
	if bus < 0: return Vector2(-80, -80)
	return Vector2(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))

func _exit_tree() -> void:
	stop(false)
	_clear_buses()
	# ActorTimeline owns and frees its own UndoRedo in NOTIFICATION_PREDELETE.
	# Releasing it here leaves that destructor holding a freed native object.


func _update_effects(bus:int,stack:Array)->void:
	var signature:=var_to_str(stack)
	if str(_track_effects.get(bus,""))==signature:return
	var generated:Array[AudioEffect]=[]
	for state in stack:
		var effect:=KiwiAudioEffects.native(state)
		if effect!=null:generated.append(effect)
	var count:=AudioServer.get_bus_effect_count(bus)-1
	var same:=count==generated.size()
	if same:
		for i in count:
			if AudioServer.get_bus_effect(bus,i).get_class()!=generated[i].get_class():same=false;break
	if same:
		for i in count:KiwiAudioEffects.update_native_properties(AudioServer.get_bus_effect(bus,i),generated[i])
	else:
		for i in maxi(0,count):AudioServer.remove_bus_effect(bus,0)
		for i in generated.size():AudioServer.add_bus_effect(bus,generated[i],i)
	_track_effects[bus]=signature
