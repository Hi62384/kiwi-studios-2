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
	for i in 8: await process_frame
func button(node: Node,text: String) -> BaseButton:
	if node is BaseButton and node.text==text: return node
	for child in node.get_children():
		var found := button(child,text)
		if found!=null: return found
	return null
func point(surface: Control,index: int,uv: Vector2,pressed: bool=true) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=surface.rect(index).position+uv*surface.rect(index).size; surface._gui_input(event)
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiTransformationWorkspace.new(); root.add_child(workspace); await settle()
	workspace.open_source(KiwiTransformationExamples.create("Talking mouth")); var session := workspace.session; session.selected_keys.assign([session.document.components[0].keys[0].id]); workspace._key_selected(); await settle()
	workspace.morph_options(); await settle(); var popup := workspace.get_node("MorphOptions") as PopupPanel
	check(popup.visible and popup.size.y<400,"Basic morph settings open compactly with advanced controls collapsed")
	var advanced := button(popup,"Advanced correspondence and appearance") as CheckButton; advanced.button_pressed=true; await settle()
	check(popup.position.y>=0 and popup.position.y+popup.size.y<=root.size.y,"Expanded advanced controls stay on-screen and scroll instead of spilling below the window")
	button(popup,"Done").pressed.emit(); await settle(); workspace.curve_dialog(); await settle()
	for child in workspace.get_children():
		if child is PopupPanel: popup=child
	button(popup,"Linear").pressed.emit(); check(is_equal_approx(session.document.components[0].keys[0].progress(.25),.25),"Linear curve template overrides Auto Morph's smooth default correctly")
	button(popup,"Ease in").pressed.emit(); check(session.document.components[0].keys[0].progress(.5)<.4,"Ease-in template changes actual transition evaluation")
	button(popup,"Ease out").pressed.emit(); check(session.document.components[0].keys[0].progress(.5)>.6,"Ease-out template changes actual transition evaluation")
	button(popup,"Done").pressed.emit(); await settle(); workspace.match_dialog(); await settle()
	var matcher: KiwiTransformationMatchEditor
	for child in workspace.get_children():
		if child is KiwiTransformationMatchEditor: matcher=child
	var count := session.undo_stack.size(); point(matcher.surface,0,Vector2(.5,.5)); point(matcher.surface,0,Vector2(.5,.5),false); point(matcher.surface,1,Vector2(.5,.52)); point(matcher.surface,1,Vector2(.5,.52),false); await settle()
	check(matcher.key().points_a.size()==1 and matcher.key().points_b.size()==1 and session.undo_stack.size()==count+1,"Pairing source and destination features creates one undoable persisted correspondence")
	var previous: Vector2=matcher.key().points_b[0]; point(matcher.surface,1,previous)
	var motion := InputEventMouseMotion.new(); motion.position=matcher.surface.rect(1).position+Vector2(.52,.54)*matcher.surface.rect(1).size; matcher.surface._gui_input(motion); point(matcher.surface,1,Vector2(.52,.54),false); await settle()
	check(matcher.key().points_b[0]!=previous and session.undo_stack.size()==count+2,"Dragging a correspondence commits exactly one correction action")
	button(matcher,"Unpair").pressed.emit(); check(matcher.key().points_a.is_empty() and matcher.surface.pending is Vector2,"Unpair keeps the source feature ready to choose a new destination")
	point(matcher.surface,1,Vector2(.5,.5)); point(matcher.surface,1,Vector2(.5,.5),false); button(matcher,"Overlays").button_pressed=false; await settle(); check(not matcher.overlays,"Comparison overlays can be hidden without changing the morph data")
	button(matcher,"Reset automatic").pressed.emit(); check(matcher.key().points_a.is_empty() and matcher.key().mode=="Auto Morph","Reset automatic removes corrections in an undoable operation")
	session.undo(); await settle(); check(matcher.key().points_a.size()==1,"Undo restores manual corrections after automatic reset")
	button(matcher,"Overlays").button_pressed=true
	point(matcher.surface,0,Vector2(.3,.5)); point(matcher.surface,0,Vector2(.3,.5),false); point(matcher.surface,1,Vector2(.35,.5)); point(matcher.surface,1,Vector2(.35,.5),false)
	var retained: Vector2=matcher.key().points_b[1]; var existing: Vector2=matcher.key().points_b[0]; count=session.undo_stack.size(); point(matcher.surface,1,retained)
	motion=InputEventMouseMotion.new(); motion.position=matcher.surface.rect(1).position+existing*matcher.surface.rect(1).size; matcher.surface._gui_input(motion); point(matcher.surface,1,existing,false); await settle()
	check(matcher.key().points_b[1]==retained and session.document.validate().is_empty() and session.undo_stack.size()==count,"Dragging a guide onto a conflicting marker cancels safely without a corrupt undo entry")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/advanced_morph_editor.png")
	matcher.hide(); await settle(); check(session.pending.is_empty(),"Closing the correction editor leaves no pending transaction")
	workspace.queue_free(); await settle(); print("MORPH_EDITOR checks=%d failures=%d"%[checks,failures]); quit(failures)
