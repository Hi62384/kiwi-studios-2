extends SceneTree
var checks := 0
var failures := 0
var workspace: KiwiTransformationWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle() -> void:
	for i in 7: await process_frame
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.button_mask=MOUSE_BUTTON_MASK_LEFT; event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiTransformationWorkspace.new(); root.add_child(workspace); await settle()
	workspace.open_source(KiwiTransformationImage2D.blank(Vector2i(320,240))); workspace.canvas.fit(); await settle()
	var session := workspace.session; var canvas := workspace.canvas; var state := session.active_state(); var blank := state.artwork.texture.get_image().get_data(); workspace.set_tool("brush"); canvas.color=Color("ef4269"); canvas.brush_size=12
	var count := session.undo_stack.size(); var p := canvas.origin()+Vector2(120,100)*canvas.zoom
	mouse(p,true); motion(p+Vector2(80,15)); mouse(p+Vector2(80,15),false); await settle()
	check(session.active_state().artwork.texture.get_image().get_data()!=blank,"Native mouse drawing updates the current component state")
	check(session.undo_stack.size()==count+1,"One continuous brush stroke creates exactly one undo action")
	session.undo(); await settle(); check(session.active_state().artwork.texture.get_image().get_data()==blank,"Brush undo restores exact blank artwork")
	session.redo(); await settle(); var painted := session.active_state(); var old_texture := painted.artwork.texture; var new_state := session.add_state(); workspace.edit_mode(); await settle()
	canvas.color=Color("57cbd1"); p=canvas.origin()+Vector2(100,140)*canvas.zoom; mouse(p,true); motion(p+Vector2(100,0)); mouse(p+Vector2(100,0),false); await settle()
	check(painted.artwork.texture==old_texture and new_state.artwork.texture!=old_texture,"Drawing a new state leaves the previous state's texture untouched")
	workspace.set_tool("move"); await settle(); var old_position := session.active_state().artwork.position; var selected := session.active_state(); var bounds := canvas.selection_bounds(); var point := canvas.origin()+bounds.get_center()*canvas.zoom
	mouse(point,true); motion(point+Vector2(35,20)); mouse(point+Vector2(35,20),false); await settle()
	check(session.active_state().artwork.position!=old_position,"Canvas move handles modify the current state transform")
	session.undo(); await settle(); check(session.active_state().artwork.position.is_equal_approx(old_position),"State movement undo restores its original position")
	workspace.open_source(KiwiTransformationExamples.create("Talking mouth")); await settle(); workspace.seek(.3); await settle()
	for i in 120:
		if workspace.animation_renderer.cache.analysis_count>0 and workspace.animation_renderer.cache.worker==null and workspace.animation_renderer.cache.requests.is_empty(): break
		await process_frame
	await settle(); await RenderingServer.frame_post_draw
	var image := workspace.animation_renderer.texture().get_image(); check(image.get_used_rect().size!=Vector2i.ZERO,"The actual GPU renderer displays multicolored animated artwork")
	var analyses := workspace.animation_renderer.cache.analysis_count; var component := workspace.session.document.components[0]; var view: Dictionary=workspace.animation_renderer.views[component.id]; var mesh_id: int=view.node.mesh.get_instance_id()
	workspace.seek(.36); await settle()
	check(workspace.animation_renderer.cache.analysis_count==analyses,"Scrubbing reuses expensive morph correspondence instead of matching every frame")
	check(view.node.mesh.get_instance_id()==mesh_id,"Playback updates shader uniforms without rebuilding the deformation mesh")
	check(workspace.canvas.previewing and not workspace.playing,"Scrubbing enters an explicit non-destructive animation preview mode")
	workspace.toggle_play(); await settle(); check(workspace.playing and workspace.session.playhead>.36,"Play advances the animation playhead")
	workspace.toggle_play(); var time := workspace.session.playhead; await settle(); check(is_equal_approx(workspace.session.playhead,time),"Pause freezes the playhead")
	var file := "user://Transformation Workspace.tres"; check(await workspace.save_to(file)==OK,"Workspace saves a native editable asset")
	var saved_session := workspace.session; var tab := workspace.capture_state(); workspace.open_source(KiwiTransformationImage2D.blank()); workspace.open_source(file,tab); await settle()
	check(workspace.session==saved_session and workspace.session.document.components[0].states.size()==4,"Tab capture preserves unsaved state data and the edit session")
	workspace.open_source(file); await settle(); check(workspace.session.document.components[0].states.size()==4 and workspace.session.document.validate().is_empty(),"Closing and reopening native data preserves all drawings and animation")
	var output := "res://.godot/verification/transformation_workspace.png"; await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output)
	var malformed_view := KiwiTransformationImage2D.blank(Vector2i(80,60)); malformed_view.workspace_state={"selected":[47,"missing"],"states":"broken","zoom":NAN,"pan":"broken","time":INF,"timeline_zoom":0,"timeline_y":-100}
	check(workspace.open_source(malformed_view),"Invalid optional view metadata does not destroy valid artwork")
	await settle(); check(workspace.session.primary()!=null and is_finite(workspace.canvas.zoom) and workspace.canvas.zoom>0 and workspace.session.playhead==0 and workspace.timeline.vertical==0,"Corrupt selection, pan, zoom and playhead metadata are safely restored to usable defaults")
	workspace.queue_free(); await settle(); print("TRANSFORMATION_WORKSPACE checks=%d failures=%d"%[checks,failures]); quit(failures)
