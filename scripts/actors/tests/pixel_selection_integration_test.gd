extends SceneTree
var failures:=0
var studio: KiwiImageWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func frames(amount: int=8) -> void:
	for i in amount: await process_frame
func check_overlay() -> void:
	var canvas:=studio.canvas
	if not canvas._selection_overlay.visible: return
	var expected:=canvas.get_global_transform()*Transform2D(0,canvas.origin()).scaled_local(Vector2.ONE*canvas.zoom)*Transform2D(0,canvas.selection_preview_origin)
	check(canvas._selection_overlay.get_global_transform().is_equal_approx(expected),"Selection overlay keeps its correct position throughout UI/layout updates")
func wait_for_smart() -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while not studio.canvas._smart_ready and studio.canvas._drag in ["object_preview","edge_pending"] and Time.get_ticks_msec()<deadline: await process_frame
func run() -> void:
	root.size=Vector2i(1400,850)
	studio=KiwiImageWorkspace.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var image:=Image.create(128,96,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	image.fill_rect(Rect2i(20,20,60,56),Color.BLACK); image.fill_rect(Rect2i(24,24,52,48),Color.BLUE)
	image.fill_rect(Rect2i(36,24,10,48),Color.RED); image.fill_rect(Rect2i(53,36,10,12),Color.WHITE)
	studio.open_source(ImageTexture.create_from_image(image)); studio._set_tool("pixel_select")
	await studio._prepare_pixel_selection(); studio.canvas.pixel_mode="object"; studio._refresh_context()
	studio._undo.clear(); studio._redo.clear()
	studio.canvas._begin_pixel_selection(Vector2(29,40)); await wait_for_smart()
	check(studio.canvas._smart_ready and studio.canvas.selected_pixel(Vector2(40,40)),"Object proposal is applied through the worker")
	check(studio._undo.is_empty(),"Proposals do not create undo entries")
	studio.canvas.set_object_threshold(.1); await wait_for_smart()
	check(not studio.canvas.selected_pixel(Vector2(40,40)),"Lowering threshold visibly removes the stripe from the live preview")
	studio.canvas.set_object_threshold(.2); studio.canvas.set_object_threshold(.5); await wait_for_smart()
	check(studio.canvas._smart_seed==Vector2(29,40) and studio.canvas.selected_pixel(Vector2(58,40)),"Slider keeps the original foreground seed and discards stale proposals")
	studio.canvas.commit_object_selection()
	check(studio._undo.size()==1 and studio.document.pixel_selection_owner==studio.canvas.selected[-1],"An object selection commits one owned undoable mask")
	studio.undo(); check(studio.document.pixel_selection==null,"Object selection undo restores the previous selection")
	studio.redo(); check(studio.document.pixel_selection!=null,"Object selection redo restores the committed mask")
	studio._save_selection_mask(false); var first:=studio.document.active_selection_mask
	check_overlay(); var history_count:=studio._undo.size()
	studio._save_selection_mask(false)
	check(studio.document.selection_masks.size()==1 and studio.document.active_selection_mask==first,"Save Mask updates the active mask instead of creating another")
	check(studio._undo.size()==history_count,"Saving an already-current mask does not create empty undo entries")
	studio._save_selection_mask(false,true)
	check(studio.document.selection_masks.size()==2 and studio.document.active_selection_mask!=first,"Save New creates and selects a separate copy")
	studio.undo(); check(studio.document.selection_masks.size()==1 and studio.document.active_selection_mask==first,"Save New supports undo")
	for frame in 4: await process_frame; check_overlay()
	studio.canvas.paint_selection_only=true; studio._set_tool("brush"); check_overlay()
	for frame in 4: await process_frame; check_overlay()
	studio._set_tool("pixel_select"); check_overlay()
	studio._save_selection_mask(true); var second:=studio.document.active_selection_mask
	check(studio.document.selection_masks.size()==2 and studio.document.pixel_selection==null,"Saved masks support a second empty working mask")
	studio._activate_selection_mask(first)
	check(studio.canvas.selected_pixel(Vector2(40,40)),"Saved selection switching restores the first mask")
	studio.undo(); check(studio.document.active_selection_mask==second,"Mask switching supports undo")
	studio.redo(); check(studio.document.active_selection_mask==first,"Mask switching supports redo")
	await studio._prepare_pixel_selection(); studio.canvas.edge_magnet=false; studio.canvas.pixel_mode="brush"; studio.canvas.pixel_box_select=false
	studio.canvas._begin_pixel_selection(Vector2(8,8)); studio.canvas._finish(Vector2(8,8))
	check_overlay()
	for frame in 4: await process_frame; check_overlay()
	check(studio.document.selection_masks[first].texture.get_image().get_pixel(8,8).a>.5,"Painting updates the active saved mask")
	studio.undo(); check(studio.document.selection_masks[first].texture.get_image().get_pixel(8,8).a==0,"Undo restores the saved mask without mutating other history entries")
	studio.redo(); check(studio.document.selection_masks[first].texture.get_image().get_pixel(8,8).a>.5,"Redo restores edits to the saved mask")
	var saved:=studio.document.snapshot()
	check(saved.selection_masks.size()==2 and saved.active_selection_mask==first,"Saved masks and active mask survive document snapshots")
	var file:="res://.godot/selection_masks_roundtrip.tres"
	check(ResourceSaver.save(saved,file)==OK,"Named selection masks serialize as editor resources")
	var loaded:=ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(loaded!=null and loaded.selection_masks.size()==2 and loaded.active_selection_mask==first,"Saved masks and active selection reopen from disk")
	var settings:=studio._ui_state(); studio.canvas.edge_magnet=true; studio.canvas.edge_threshold=.63; studio.canvas.object_threshold=.72
	settings=studio._ui_state(); check(settings.edge_magnet and is_equal_approx(settings.edge_threshold,.63) and is_equal_approx(settings.object_threshold,.72),"Smart selection settings are persisted")
	await studio._prepare_pixel_selection(); studio.canvas.pixel_mode="object"
	studio.canvas._begin_pixel_selection(Vector2(29,40)); await wait_for_smart()
	check(not studio.canvas.selected_pixel(Vector2(8,8)),"Normal object clicks replace old selected pixels rather than hiding threshold changes underneath them")
	studio.canvas.cancel_gesture(); await frames()
	studio.canvas._begin_pixel_selection(Vector2(29,40),true); await wait_for_smart()
	check(studio.canvas.selected_pixel(Vector2(8,8)),"Shift object clicks preserve the existing selection")
	studio.canvas.cancel_gesture(); await frames()
	studio.canvas._begin_pixel_selection(Vector2(29,40)); studio.canvas.cancel_gesture(); await frames(30)
	check(studio.canvas._drag.is_empty() and studio.document.active_selection_mask==first,"Cancel rejects stale worker results")
	studio._set_tool("effects"); check(studio.inspector.visible and not studio._effects_dock.visible,"Effects no longer replace layer properties")
	studio._open_stack_editor(false); var editor:=studio.get_node("EffectStackEditor")
	editor.add_entry("invert"); await frames(16)
	check(editor.preview.texture!=null and studio.document.layers[0].effects.size()==1,"Effect stack has a live GPU preview")
	editor.whole=true; await frames()
	check(editor.preview.texture==studio.renderer.texture(),"Whole-viewport preview is selectable")
	editor.search.text="mirror"; editor.search.text_changed.emit("mirror")
	check(editor.library.get_child_count()==1,"Effect library search filters available effects")
	await frames(4); editor.get_texture().get_image().save_png("res://.godot/effects_stack_ui.png")
	editor.close_editor(); await frames()
	studio._set_tool("values"); studio._open_stack_editor(true); editor=studio.get_node("AdjustmentStackEditor")
	editor.add_entry("brightness"); editor.add_entry("contrast"); editor.add_entry("vibrance"); editor.move_entry(2,0)
	check(studio.document.layers[0].properties.value_operations[0].type=="vibrance","Adjustment stack supports adding and reordering real color operations")
	await frames(16); check(editor.preview.texture!=null,"Adjustment stack has a live GPU preview")
	check(editor.library.get_child_count()>20,"Adjustment library exposes the full set of available color operations")
	editor.get_texture().get_image().save_png("res://.godot/adjustment_stack_ui.png")
	editor.close_editor(); await frames()
	studio.free(); await frames(2)
	print("Pixel selection / stacks integration checks: %d failures" % failures); quit(failures)
