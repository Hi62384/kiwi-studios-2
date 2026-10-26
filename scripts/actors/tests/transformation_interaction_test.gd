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
	for i in 6: await process_frame
func mouse(control: Control,point: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=control.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func motion(control: Control,point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.button_mask=MOUSE_BUTTON_MASK_LEFT; event.position=control.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func numbers(node: Node) -> Array[DragNumber]:
	var found: Array[DragNumber]=[]
	for child in node.get_children():
		if child is DragNumber: found.append(child)
		found.append_array(numbers(child))
	return found
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiTransformationWorkspace.new(); root.add_child(workspace); await settle()
	workspace.open_source(KiwiTransformationImage2D.blank(Vector2i(320,240))); workspace.canvas.fit(); workspace.set_tool("shape"); await settle()
	var canvas := workspace.canvas; var session := workspace.session; var start := canvas.origin()+Vector2(90,70)*canvas.zoom; var end := canvas.origin()+Vector2(220,170)*canvas.zoom
	canvas.color=Color("e84772"); mouse(canvas,start,true); motion(canvas,end); mouse(canvas,end,false); await settle()
	check(session.active_state().artwork.texture.get_image().get_pixel(150,100).r>.8,"Native shape drag paints multicolored raster state artwork")
	workspace.set_tool("pivot"); await settle(); var p := canvas.origin()+Vector2(160,120)*canvas.zoom; var target := canvas.origin()+Vector2(60,80)*canvas.zoom
	var old_texture := session.active_state().artwork.texture; var old_position := session.active_state().artwork.position
	mouse(canvas,p,true); motion(canvas,target); mouse(canvas,target,false); await settle()
	check(session.active_state().pivot.is_equal_approx(Vector2(60./320.,80./240.)),"Dragging the pivot edits its normalized component anchor")
	check(session.active_state().artwork.position==old_position and session.active_state().artwork.texture==old_texture,"Editing the pivot does not shift or repaint the drawing")
	session.undo(); await settle(); check(session.active_state().pivot.is_equal_approx(Vector2(.5,.5)),"Pivot editing is one undoable operation")
	session.redo(); await settle(); workspace.set_tool("move"); await settle()
	var state := session.active_state(); var anchor := state.anchor(); var bounds := canvas.selection_bounds(); var handle := canvas._rotation_handle(Rect2(canvas.origin()+bounds.position*canvas.zoom,bounds.size*canvas.zoom)); var center := canvas.origin()+anchor*canvas.zoom; var rotated := center+Vector2.from_angle((handle-center).angle()+.7)*(handle-center).length()
	mouse(canvas,handle,true); motion(canvas,rotated); mouse(canvas,rotated,false); await settle()
	check(absf(session.active_state().artwork.rotation)>.2 and session.active_state().anchor().is_equal_approx(anchor),"Native rotation handles rotate artwork around its chosen pivot")
	session.undo(); await settle(); await workspace.set_tool("pixel_select"); canvas.pixel_box_select=true; await settle()
	start=canvas.origin()+Vector2(110,90)*canvas.zoom; end=canvas.origin()+Vector2(180,150)*canvas.zoom
	mouse(canvas,start,true); motion(canvas,end); mouse(canvas,end,false); await settle()
	check(session.pixel_mask!=null and canvas.selection_coverage(Vector2(150,110))>.9 and canvas.selection_coverage(Vector2(30,30))<.1,"Native pixel selection selects the chosen region, not the whole viewport")
	session.undo(); await settle(); check(canvas.selection==null,"Pixel selection undo restores an empty mask")
	session.redo(); await settle(); check(canvas.selection!=null,"Pixel selection redo restores the mask")
	workspace.extract_selection(); await settle()
	check(session.document.components.size()==2 and session.active_state().artwork.texture.get_image().get_used_rect().has_area(),"Extract selected pixels creates a separate editable component")
	session.undo(); await settle(); check(session.document.components.size()==1,"Pixel extraction undo restores the source component and its artwork")
	workspace.open_source(KiwiTransformationExamples.create("Talking mouth")); session=workspace.session; await settle()
	var timeline := workspace.timeline; var component := session.document.components[0]; var key := component.keys[1]; var previous := key.time; var point := Vector2(timeline.x(key.time),timeline.row_y(0)+13)
	mouse(timeline,point,true); motion(timeline,point+Vector2(25,0)); mouse(timeline,point+Vector2(25,0),false); await settle()
	check(session.document.components[0].keys[1].time>previous and session.document.validate().is_empty(),"Native timeline key drag moves and snaps a reusable state instance")
	session.undo(); await settle(); check(is_equal_approx(session.document.components[0].keys[1].time,previous),"Timeline key movement supports undo")
	component=session.document.components[0]; session.selected_keys.assign([component.keys[1].id]); workspace._key_selected(); await settle()
	var fields := numbers(workspace.key_fields); var count := session.undo_stack.size(); fields[0].value=component.keys[2].time; await settle()
	check(session.document.validate().is_empty() and is_equal_approx(session.document.components[0].keys[1].time,previous) and session.undo_stack.size()==count,"Overlapping key times entered in the inspector are rejected without corrupting history")
	workspace.edit_mode(); await settle(); fields=numbers(workspace.properties); var input := fields[0]; count=session.undo_stack.size()
	input._begin_drag(Vector2(400,400)); input.dragging=true; input.interaction_started.emit(); input.drag_pixels(8,false,false); input.drag_pixels(-8,false,false); input.finish_drag(); await settle()
	check(session.pending.is_empty() and not workspace._number_drag and session.undo_stack.size()==count,"A numeric drag returned to its start releases its no-op transaction")
	workspace.seek(.2); await settle(); count=session.undo_stack.size(); workspace.time_control.value=.4; await settle()
	check(session.undo_stack.size()==count and is_equal_approx(session.playhead,.4),"Typing the playhead time changes the view without adding an asset edit")
	workspace.queue_free(); await settle(); print("TRANSFORMATION_INTERACTION checks=%d failures=%d"%[checks,failures]); quit(failures)
