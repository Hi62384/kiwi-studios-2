class_name ActorSceneExporter
extends RefCounted
## Renders the actual scene SubViewport at discrete timeline times, then encodes it.

static func render(editor: ActorTimelineEditor, destination: String, width: int,
		height: int, fps: int, progress: Callable = Callable(),options: Dictionary={}) -> String:
	var encoder := ActorVideo.executable("ffmpeg")
	if encoder.is_empty(): return "FFmpeg is required to export an MP4 video."
	var viewport := editor.get_node_or_null("../../../../World/SubViewport") as SubViewport
	if viewport == null: return "The scene viewport is unavailable."
	if not is_instance_valid(editor.runtime_holder): return "Scene actors are not ready to render."
	if destination.is_empty(): return "Choose an output file."
	var output := ProjectSettings.globalize_path(destination)
	var output_directory := output.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		return "The output directory does not exist."
	var frame_count := maxi(1, ceili(editor.video_duration * fps))
	var samples:=clampi(int(options.get("motion_samples",1)),1,8); var shutter:=clampf(float(options.get("shutter",.5)),0,1)
	if shutter<=0.: samples=1
	var input_count:=frame_count*samples; var previous_sample:=0.
	var frame_directory := ProjectSettings.globalize_path("user://scene_export/" + ActorData.new_id())
	var error := DirAccess.make_dir_recursive_absolute(frame_directory)
	if error != OK: return "Could not create temporary frame directory."
	var old_time := editor.canvas.playhead
	var old_playing := editor.playing
	var old_size := viewport.size
	var old_update := viewport.render_target_update_mode
	var old_msaa:=viewport.msaa_3d
	if options.has("msaa"): viewport.msaa_3d=clampi(int(options.msaa),0,3)
	var old_growth_quality: Variant=viewport.get_meta("kiwi_final_growth") if viewport.has_meta("kiwi_final_growth") else null
	viewport.set_meta("kiwi_final_growth",true)
	var old_capture: Variant=viewport.get_meta("kiwi_scene_frame_capture") if viewport.has_meta("kiwi_scene_frame_capture") else null
	viewport.set_meta("kiwi_scene_frame_capture",true)
	var old_camera := viewport.get_camera_3d()
	var free_camera := viewport.get_node_or_null("Freecam/Head/Camera3D") as Camera3D
	var old_free_mask := free_camera.cull_mask if free_camera != null else 1
	var particle_states: Array[Dictionary] = []
	for type_name in ["GPUParticles3D", "GPUParticles2D", "CPUParticles3D", "CPUParticles2D"]:
		for particle in editor.runtime_holder.find_children("*", type_name, true, false):
			particle_states.append({"node": particle, "speed": particle.get("speed_scale"), "active": false})
			particle.set("speed_scale", 0.0)
	editor.playing = false
	editor.exporting = true
	if free_camera != null: free_camera.cull_mask = 1
	if editor.play_button != null: editor.play_button.text = "▶"
	viewport.size = Vector2i(width, height)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var failure := ""
	for frame in input_count:
		editor.canvas.playhead = temporal_sample_time(frame,samples,fps,shutter)
		failure = await _wait_video_frames(editor, editor.canvas.playhead)
		if not failure.is_empty(): break
		editor._evaluate_runtimes()
		while editor.physics.pending:
			await editor.get_tree().process_frame
			editor._evaluate_runtimes()
		_render_camera_for_time(editor, viewport, free_camera, editor.canvas.playhead)
		failure = await _wait_environment_geometry(editor)
		if not failure.is_empty(): break
		# All actors and the export camera have now been sampled. Synchronize fog
		# ownership before this exact frame rather than waiting for a later process tick.
		var environment_world:=viewport.get_node_or_null("KiwiEnvironmentWorld")
		if environment_world!=null: environment_world._process(0.)
		var fog_environment:=viewport.get_node_or_null("KiwiFogEnvironment")
		if fog_environment!=null: fog_environment._process(0.)
		editor._update_camera_overlays()
		for index in particle_states.size():
			var state: Dictionary = particle_states[index]
			if not is_instance_valid(state.node): continue
			var active: bool = state.node.is_visible_in_tree() and bool(state.node.get("emitting"))
			if active and not bool(state.active): state.node.restart()
			if active and state.node.has_method("request_particles_process"):
				state.node.request_particles_process(1.0 / fps if samples==1 else maxf(0.,editor.canvas.playhead-previous_sample))
			state.active = active
			particle_states[index] = state
		if DisplayServer.get_name() == "headless":
			await editor.get_tree().process_frame
			await editor.get_tree().process_frame
		else:
			# The first resized Forward+ frame also allocates volumetric buffers and
			# uploads initial 3D concentration textures. Two draw passes can still
			# return the uninitialized black target. Warm those resources at the
			# SAME sampled time; no particle/physics request is repeated here.
			for pass_index in (6 if frame==0 else 2): await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			failure = "The viewport returned an empty frame."
			break
		var frame_path := frame_directory.path_join("frame_%06d.png" % frame)
		if image.save_png(frame_path) != OK:
			failure = "Could not write a rendered frame."
			break
		previous_sample=editor.canvas.playhead
		if progress.is_valid() and (frame+1)%samples==0: progress.call((frame+1)/samples, frame_count, "Rendering")
		await editor.get_tree().process_frame
	viewport.size = old_size
	viewport.render_target_update_mode = old_update
	viewport.msaa_3d=old_msaa
	if old_growth_quality==null: viewport.remove_meta("kiwi_final_growth")
	else: viewport.set_meta("kiwi_final_growth",old_growth_quality)
	if old_capture==null: viewport.remove_meta("kiwi_scene_frame_capture")
	else: viewport.set_meta("kiwi_scene_frame_capture",old_capture)
	if free_camera != null: free_camera.cull_mask = old_free_mask
	editor.canvas.playhead = old_time
	editor.playing = old_playing
	editor.exporting = false
	if editor.play_button != null: editor.play_button.text = "Ⅱ" if old_playing else "▶"
	editor._evaluate_runtimes()
	if free_camera != null: free_camera.make_current()
	elif is_instance_valid(old_camera): old_camera.make_current()
	for state in particle_states:
		if is_instance_valid(state.node):
			state.node.set("speed_scale", state.speed)
			state.node.restart()
			if state.node.has_method("request_particles_process"):
				state.node.request_particles_process(maxf(0.0, old_time))
	if not failure.is_empty():
		_cleanup_frames(frame_directory, input_count)
		return failure
	if progress.is_valid(): progress.call(frame_count, frame_count, "Encoding")
	var arguments := PackedStringArray(["-hide_banner", "-loglevel", "error", "-nostdin", "-y",
		"-framerate", str(fps*samples), "-i", frame_directory.path_join("frame_%06d.png")])
	var audio_filters := PackedStringArray()
	var audio_count := 0
	for index in editor.model.actors.size():
		var actor := editor.model.actors[index]
		if actor.type_id != &"audio" or bool(actor.get_value(&"muted", false)): continue
		var clip := editor.model.clips[index]
		if clip.start_time >= editor.video_duration or clip.start_time + clip.duration <= 0.0: continue
		var source := _audio_source(actor.values.get(&"audio", ""), frame_directory, audio_count)
		if source.is_empty(): continue
		var active_duration := minf(clip.duration, editor.video_duration - clip.start_time)
		if active_duration <= 0.0: continue
		arguments.append_array(PackedStringArray(["-i", source]))
		audio_filters.append(_audio_filter(actor, clip, audio_count, active_duration))
		audio_count += 1
	if audio_count > 0:
		var labels := ""
		for index in audio_count: labels += "[a%d]" % index
		if audio_count == 1:
			audio_filters.append("[a0]atrim=duration=%s,asetpts=PTS-STARTPTS[aout]" % editor.video_duration)
		else:
			audio_filters.append("%samix=inputs=%d:duration=longest:dropout_transition=0,atrim=duration=%s,asetpts=PTS-STARTPTS[aout]" % [labels, audio_count, editor.video_duration])
		arguments.append_array(PackedStringArray(["-filter_complex", ";".join(audio_filters), "-map", "0:v:0", "-map", "[aout]"]))
	else:
		arguments.append_array(PackedStringArray(["-map", "0:v:0"]))
	if samples>1: arguments.append_array(PackedStringArray(["-vf","tmix=frames=%d:weights='%s',select='not(mod(n+1,%d))',setpts=N/(%d*TB)"%[samples,"1 ".repeat(samples).strip_edges(),samples,fps]]))
	arguments.append_array(PackedStringArray(["-frames:v", str(frame_count),
		"-r",str(fps),
		"-c:v", "libx264", "-preset", "medium",
		"-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", output]))
	if audio_count > 0:
		arguments.insert(arguments.size() - 1, "-c:a")
		arguments.insert(arguments.size() - 1, "aac")
		arguments.insert(arguments.size() - 1, "-b:a")
		arguments.insert(arguments.size() - 1, "192k")
	var job := OS.execute_with_pipe(encoder, arguments, false)
	if job.is_empty():
		_cleanup_frames(frame_directory, input_count)
		return "FFmpeg could not start."
	var stderr: String = ""
	while OS.is_process_running(job.pid):
		stderr += job.stderr.get_buffer(4096).get_string_from_utf8()
		await editor.get_tree().process_frame
	var exit_code := OS.get_process_exit_code(job.pid)
	_cleanup_frames(frame_directory, input_count)
	if exit_code != 0 or not FileAccess.file_exists(output):
		return "Video encoding failed. " + stderr.right(500)
	return ""


static func temporal_sample_time(frame: int,samples: int,fps: int,shutter: float) -> float:
	var nominal:=float(frame/samples)/fps
	return maxf(0.,nominal+((float(frame%samples)+.5)/samples-.5)*shutter/fps) if samples>1 else nominal

static func _render_camera_for_time(editor: ActorTimelineEditor, viewport: SubViewport,
		fallback: Camera3D, time: float) -> Camera3D:
	var chosen: Camera3D
	for index in editor.model.actors.size():
		if editor.model.actors[index].type_id != &"camera_3d" or not editor.model.clips[index].contains_time(time):
			continue
		var runtime := editor._runtime_for_clip(editor.model.clips[index].id)
		if runtime != null and runtime.active and runtime.get("content") is Camera3D:
			chosen = runtime.get("content") as Camera3D
	if chosen == null: chosen = fallback
	if chosen != null and viewport.get_camera_3d() != chosen: chosen.make_current()
	return chosen


static func _wait_environment_geometry(editor: ActorTimelineEditor) -> String:
	var actors: Array[Dictionary] = []
	for index in editor.model.actors.size():
		var actor := editor.model.actors[index]
		if actor.type_id != &"environment_asset" or not editor.model.clips[index].contains_time(editor.canvas.playhead): continue
		var runtime := editor._runtime_for_clip(editor.model.clips[index].id)
		if is_instance_valid(runtime) and runtime.has_method("render_geometry_ready"):
			actors.append({"runtime":runtime,"title":actor.title})
	if actors.is_empty(): return ""
	var deadline := Time.get_ticks_msec() + 90000
	while true:
		var all_ready := true
		for entry: Dictionary in actors:
			var runtime: Object = entry.runtime
			if not is_instance_valid(runtime): continue
			var issue := str(runtime.call("render_geometry_error")) if runtime.has_method("render_geometry_error") else ""
			if not issue.is_empty(): return str(entry.title)+": "+issue
			if not bool(runtime.call("render_geometry_ready")): all_ready = false
		if all_ready: return ""
		if Time.get_ticks_msec() >= deadline: return "Timed out preparing environment geometry for the export camera."
		await editor.get_tree().process_frame
	return ""


static func _wait_video_frames(editor: ActorTimelineEditor, time: float) -> String:
	for index in editor.model.actors.size():
		var actor := editor.model.actors[index]
		if actor.type_id not in [&"video", &"video_2d"]: continue
		var clip := editor.model.clips[index]
		if not clip.contains_time(time): continue
		var path := str(actor.get_value(&"video", ""))
		if path.is_empty(): continue
		var deadline := Time.get_ticks_msec() + 30000
		while ActorVideo.frame(path, clip.local_time(time), true) == null:
			if Time.get_ticks_msec() >= deadline:
				return "Timed out decoding a video frame from %s." % path.get_file()
			await editor.get_tree().process_frame
	return ""


static func _cleanup_frames(directory: String, _count: int) -> void:
	for file_name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file_name))
	DirAccess.remove_absolute(directory)


static func _audio_source(value: Variant, temporary_directory: String, index: int) -> String:
	if value is String and FileAccess.file_exists(value) and value.get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"]:
		return ProjectSettings.globalize_path(value)
	var stream := ActorAudio.source(value)
	if stream == null: return ""
	if not stream.resource_path.is_empty() and stream.resource_path.get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"]:
		return ProjectSettings.globalize_path(stream.resource_path)
	if stream is AudioStreamWAV:
		var path := temporary_directory.path_join("audio_%d.wav" % index)
		return path if stream.save_to_wav(path) == OK else ""
	if stream is AudioStreamMP3:
		var path := temporary_directory.path_join("audio_%d.mp3" % index)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return ""
		file.store_buffer(stream.data)
		file.close()
		return path
	# Imported or embedded streams without a source path can still be decoded by
	# Godot's own playback before FFmpeg performs the final timeline mix.
	var rate := maxi(1, int(AudioServer.get_mix_rate()))
	var frames := maxi(0, ceili(stream.get_length() * rate))
	if frames == 0: return ""
	var pcm := PackedByteArray()
	pcm.resize(frames * 4)
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var cursor := 0
	while cursor < frames:
		var samples := playback.mix_audio(1.0, mini(4096, frames - cursor))
		if samples.is_empty(): break
		for sample in samples:
			pcm.encode_s16(cursor * 4, clampi(roundi(sample.x * 32767.0), -32768, 32767))
			pcm.encode_s16(cursor * 4 + 2, clampi(roundi(sample.y * 32767.0), -32768, 32767))
			cursor += 1
	playback.stop()
	if cursor == 0: return ""
	pcm.resize(cursor * 4)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = rate
	wav.data = pcm
	var path := temporary_directory.path_join("audio_%d.wav" % index)
	return path if wav.save_to_wav(path) == OK else ""


static func _audio_filter(actor: ActorData, clip: ActorClip, index: int, duration: float) -> String:
	var speed := maxf(0.01, clip.playback_speed)
	var pitch := maxf(0.01, float(actor.get_value(&"pitch", 1.0)))
	var filters := PackedStringArray([
		"atrim=start=%s:duration=%s" % [clip.source_offset, duration * speed],
		"asetpts=PTS-STARTPTS", "aresample=44100",
		"asetrate=%d" % roundi(44100.0 * pitch), "aresample=44100"])
	var tempo := speed / pitch
	while tempo > 2.0:
		filters.append("atempo=2.0")
		tempo /= 2.0
	while tempo < 0.5:
		filters.append("atempo=0.5")
		tempo *= 2.0
	filters.append("atempo=%s" % tempo)
	filters.append("volume=%s" % db_to_linear(float(actor.get_value(&"volume_db", 0.0))))
	filters.append(KiwiAudioEffects.pan_filter(float(actor.get_value(&"pan",0.0))))
	var fade_in := minf(duration, maxf(0.0, float(actor.get_value(&"fade_in", 0.0))))
	var fade_out := minf(duration, maxf(0.0, float(actor.get_value(&"fade_out", 0.0))))
	if fade_in > 0.0: filters.append("afade=t=in:st=0:d=%s" % fade_in)
	if fade_out > 0.0: filters.append("afade=t=out:st=%s:d=%s" % [maxf(0.0, duration - fade_out), fade_out])
	filters.append("adelay=%d:all=1" % roundi(maxf(0.0, clip.start_time) * 1000.0))
	return "[%d:a]%s[a%d]" % [index + 1, ",".join(filters), index]
