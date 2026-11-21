class_name ActorSceneExporter
extends RefCounted
## Renders the actual scene SubViewport at discrete timeline times, then encodes it.

static func render(editor: ActorTimelineEditor, destination: String, width: int,
		height: int, fps: int, progress: Callable = Callable(),options: Dictionary={}) -> String:
	var job: Dictionary=_native().prepare(editor,destination,width,height,fps,options)
	if not str(job.error).is_empty(): return str(job.error)
	var failure := ""
	for frame in int(job.input_count):
		_native().begin_frame(editor,job,frame)
		failure = await _wait_video_frames(editor,editor.canvas.playhead)
		if not failure.is_empty(): break
		editor._evaluate_runtimes()
		while editor.physics.pending:
			await editor.get_tree().process_frame
			editor._evaluate_runtimes()
		_render_camera_for_time(editor,job.viewport,job.free_camera,editor.canvas.playhead)
		failure = await _wait_environment_geometry(editor)
		if not failure.is_empty(): break
		_native().synchronize_frame(editor,job)
		if DisplayServer.get_name() == "headless":
			await editor.get_tree().process_frame
			await editor.get_tree().process_frame
		else:
			for pass_index in (6 if frame==0 else 2): await RenderingServer.frame_post_draw
		failure = _native().save_frame(editor,job,frame)
		if not failure.is_empty(): break
		if progress.is_valid() and (frame+1)%int(job.samples)==0: progress.call((frame+1)/int(job.samples),job.frame_count,"Rendering")
		await editor.get_tree().process_frame
	_native().restore(editor,job)
	if not failure.is_empty():
		_cleanup_frames(job.frame_directory,job.input_count)
		return failure
	if progress.is_valid(): progress.call(job.frame_count,job.frame_count,"Encoding")
	failure = _native().start_encoding(editor,job)
	if not failure.is_empty(): return failure
	while _native().encoding_running(job): await editor.get_tree().process_frame
	return _native().finish_encoding(job)


static func temporal_sample_time(frame: int,samples: int,fps: int,shutter: float) -> float:
	return _native().temporal_sample_time(frame,samples,fps,shutter)

static func _render_camera_for_time(editor: ActorTimelineEditor, viewport: SubViewport,
		fallback: Camera3D, time: float) -> Camera3D:
	return _native().render_camera_for_time(editor,viewport,fallback,time)

static func _wait_environment_geometry(editor: ActorTimelineEditor) -> String:
	var actors: Array=_native().environment_targets(editor)
	if actors.is_empty(): return ""
	var deadline := Time.get_ticks_msec() + 90000
	while true:
		var state: Dictionary=_native().environment_status(actors)
		if not str(state.error).is_empty(): return str(state.error)
		if state.ready: return ""
		if Time.get_ticks_msec() >= deadline: return "Timed out preparing environment geometry for the export camera."
		await editor.get_tree().process_frame
	return ""

static func _wait_video_frames(editor: ActorTimelineEditor, time: float) -> String:
	for target: Dictionary in _native().video_targets(editor,time):
		var path: String=target.path
		var deadline := Time.get_ticks_msec() + 30000
		while ActorVideo.frame(path,target.time,true) == null:
			if Time.get_ticks_msec() >= deadline: return "Timed out decoding a video frame from %s." % path.get_file()
			await editor.get_tree().process_frame
	return ""

static func _cleanup_frames(directory: String, _count: int) -> void:
	_native().cleanup_frames(directory,_count)

static func _audio_source(value: Variant, temporary_directory: String, index: int) -> String:
	return _native().audio_source(value,temporary_directory,index)

static func _audio_filter(actor: ActorData, clip: ActorClip, index: int, duration: float) -> String:
	return _native().audio_filter(actor,clip,index,duration)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("actor_scene_export")
