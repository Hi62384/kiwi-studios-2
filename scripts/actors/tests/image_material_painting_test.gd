extends SceneTree
class TestStudio extends KiwiImageWorkspace:
	func _persist_paint_presets(_path: String=PAINT_PRESETS_PATH) -> void:
		if _path!=PAINT_PRESETS_PATH: super._persist_paint_presets(_path)
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var failures:=0
var checks:=0
var studio: KiwiImageWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)
func frames(count: int=4) -> void:
	for i in count: await process_frame
func output() -> Image:
	studio.renderer.sync(studio.document)
	return await studio.renderer.flattened()
func active_layer() -> KiwiImageLayer: return studio.document.layers[0]
func run() -> void:
	root.size=Vector2i(1440,900); root.gui_embed_subwindows=true
	studio=TestStudio.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source:=Image.create(96,64,false,Image.FORMAT_RGBA8); source.fill(Color.TRANSPARENT)
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("brush")
	studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=true
	studio.canvas.repair_tool.material=Library.create("wood/oak"); studio.canvas.brush_type="normal"
	studio.canvas.brush_size=16; studio.canvas.hardness=1; studio.canvas.brush_opacity=.7; studio.canvas.paint_selection_only=false
	studio._refresh_context()
	check(studio.find_child("PaintingMode",true,false)!=null,"Brush has compact Color / Material selector")
	check(studio.live_material_panel.visible,"Live templates occupy third toolbar row")
	await studio.canvas._begin_paint(Vector2(18,18)); studio.canvas._paint_line(Vector2(18,18),Vector2(34,18)); await studio.canvas._finish(Vector2(34,18))
	var first_id:=studio.document.active_live_material_id
	check(studio.document.live_materials.size()==1,"First linked brush gesture creates one template")
	check(active_layer().live_paint.size()==1,"Brush coverage lives separately from raster paint")
	var region=active_layer().live_paint[0]
	check(region.coverage.get_image().get_pixel(24,18).a>.6 and region.coverage.get_image().get_pixel(24,18).a<.75,"Material brush preserves opacity")
	check(region.coverage.get_image().get_pixel(70,50).a==0,"Material brush preserves coverage shape")
	var size_before:=studio.canvas.brush_size
	var wood:=studio.canvas.repair_tool.material.copy_material(); wood.texture_size=180; studio._material_changed(wood); studio._commit()
	check(studio.canvas.brush_size==size_before,"Texture size remains independent from brush size")
	await studio.canvas._begin_paint(Vector2(65,18)); await studio.canvas._finish(Vector2(65,18))
	check(active_layer().live_paint.size()==1,"Consecutive linked regions reuse their coverage surface")
	var before: Image=await output(); var coverage:=active_layer().live_paint[0].coverage.get_image().get_data()
	wood.parameters.primary=Color.RED; wood.parameters.secondary=Color.YELLOW; studio._material_changed(wood); studio._commit()
	var after: Image=await output()
	check(before.get_pixel(24,18)!=after.get_pixel(24,18),"Changing template colors updates first painted region")
	check(before.get_pixel(65,18)!=after.get_pixel(65,18),"Changing template colors updates later region without repainting")
	check(active_layer().live_paint[0].coverage.get_image().get_data()==coverage,"Material edits leave exact coverage unchanged")
	studio._action(func(): studio.document.create_live_material(Library.create("fabric/denim")))
	studio._select_live_material(studio.document.active_live_material_id)
	var second_id:=studio.document.active_live_material_id
	await studio.canvas._begin_paint(Vector2(65,44)); await studio.canvas._finish(Vector2(65,44))
	var second_before: Image=await output()
	studio._select_live_material(first_id); wood.parameters.primary=Color.GREEN; wood.parameters.secondary=Color.CYAN; studio._material_changed(wood); studio._commit()
	var second_after: Image=await output()
	check(second_before.get_pixel(65,44)==second_after.get_pixel(65,44),"Editing first template leaves other template's pixels unchanged")
	studio._action(func(): studio.document.delete_live_material(first_id))
	check(studio.document.live_material_for_id(first_id)==null and studio.document.live_material_for_id(second_id)!=null,"Delete targets explicit template ownership")
	studio.undo(); check(studio.document.live_material_for_id(first_id)!=null,"Undo restores deleted template and ownership")
	studio._select_live_material(second_id); var prebake: Image=await output(); await studio._bake_active_material(); var postbake: Image=await output()
	check(studio.document.live_material_for_id(second_id)==null,"Bake removes template linkage")
	check(prebake.get_pixel(65,44).is_equal_approx(postbake.get_pixel(65,44)),"Bake preserves appearance of isolated owned artwork")
	studio.undo(); check(studio.document.live_material_for_id(second_id)!=null,"Undo bake restores editability")
	# Save resources, reload them, and prove that masks and IDs survive serialization.
	var snapshot:=studio.document.snapshot(); studio._pack_project_textures(snapshot)
	check(ResourceSaver.save(snapshot,"user://material_workflow_test.tres")==OK,"Live document saves with compressed masks")
	var loaded:=ResourceLoader.load("user://material_workflow_test.tres","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(loaded!=null and loaded.live_materials.size()==2 and loaded.layers[0].live_paint.size()==2,"Save/reopen retains templates and region ownership")
	# Use the existing stroke corrector rather than a second brush implementation.
	studio._select_live_material(first_id); studio.canvas.brush_type="stroke_correct"; studio.canvas.correction_strength=.7
	await studio.canvas._begin_paint(Vector2(12,44))
	for point in [Vector2(20,43),Vector2(26,46),Vector2(36,44)]:
		studio.canvas._corrector.add(point,Time.get_ticks_usec()/1000000.0+.03); studio.canvas._flush_corrected_stroke()
	await studio.canvas._finish(Vector2(36,44))
	check(active_layer().live_paint[-1].coverage.get_image().get_used_rect().has_area(),"Stroke Correct writes linked material coverage")
	# Material bucket uses color tolerance, connectedness, and fractional selections.
	var blocks:=Image.create(32,24,false,Image.FORMAT_RGBA8); blocks.fill(Color.WHITE); blocks.fill_rect(Rect2i(10,0,2,24),Color.BLACK); blocks.fill_rect(Rect2i(20,0,2,24),Color.BLACK)
	studio.open_source(ImageTexture.create_from_image(blocks)); studio._set_tool("fill"); studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=true; studio.canvas.brush_type="normal"; studio.canvas.brush_opacity=1; studio.canvas.material_strength=1; studio.canvas.fill_threshold=.01
	await studio.canvas._begin_paint(Vector2(3,4)); await frames()
	region=active_layer().live_paint[-1]
	check(region.coverage.get_image().get_pixel(3,4).a==1,"Bucket fills clicked connected region")
	check(region.coverage.get_image().get_pixel(16,4).a==0 and region.coverage.get_image().get_pixel(10,4).a==0,"Bucket does not cross color boundaries or jump disconnected regions")
	studio.undo()
	var selection:=Image.create(32,24,false,Image.FORMAT_RGBA8); selection.fill_rect(Rect2i(0,0,6,12),Color(1,1,1,.5))
	studio.document.pixel_selection=ImageTexture.create_from_image(selection); studio.document.pixel_selection_owner=active_layer().id; studio.canvas.sync_pixel_selection(); studio.canvas.paint_selection_only=true
	await studio.canvas._begin_paint(Vector2(3,4)); await frames()
	region=active_layer().live_paint[-1]
	check(region.coverage.get_image().get_pixel(3,4).a>.49 and region.coverage.get_image().get_pixel(3,4).a<.51,"Material bucket respects fractional selection alpha")
	check(region.coverage.get_image().get_pixel(8,4).a==0,"Material bucket clips to selected pixels")
	# Non-live painting becomes real editable raster pixels on the same layer.
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("brush")
	studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=false; studio.canvas.paint_selection_only=false
	studio.canvas.brush_type="normal"; studio.canvas.brush_opacity=1; studio.canvas.brush_size=16; studio.canvas.hardness=1
	await studio.canvas._begin_paint(Vector2(24,24)); await studio.canvas._finish(Vector2(24,24))
	check(studio.document.live_materials.is_empty() and active_layer().live_paint.is_empty(),"Non-live Material brush bakes its temporary template")
	check(active_layer().texture.get_image().get_pixel(24,24).a>.9,"Non-live Material brush writes ordinary raster pixels")
	studio._set_tool("eraser"); await studio.canvas._begin_paint(Vector2(24,24)); await studio.canvas._finish(Vector2(24,24))
	check(active_layer().texture.get_image().get_pixel(24,24).a<.1,"Baked Material brush pixels can be erased normally")
	studio.open_source(ImageTexture.create_from_image(blocks)); studio._set_tool("fill"); studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=false
	await studio.canvas._begin_paint(Vector2(3,4))
	while studio.canvas._material_busy: await process_frame
	check(studio.document.live_materials.is_empty() and active_layer().live_paint.is_empty(),"Non-live Material bucket produces ordinary raster output")
	check(active_layer().texture.get_image().get_pixel(3,4)!=Color.WHITE and active_layer().texture.get_image().get_pixel(16,4)==Color.WHITE,"Non-live material fill preserves connected-region boundaries")
	# Alternating linked and ordinary paint preserves exact draw order.
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("brush"); studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=true
	studio.canvas.brush_size=20; studio.canvas.brush_opacity=1; studio.canvas.hardness=1
	await studio.canvas._begin_paint(Vector2(32,32)); await studio.canvas._finish(Vector2(32,32))
	var order_template:=studio.document.active_live_material_id
	studio.canvas.painting_mode="color"; studio.canvas.color=Color.RED
	await studio.canvas._begin_paint(Vector2(32,32)); await studio.canvas._finish(Vector2(32,32))
	var order_image: Image=await output(); check(order_image.get_pixel(32,32).r>.95 and order_image.get_pixel(32,32).g<.02,"Color paint lies above preceding linked material")
	studio.canvas.painting_mode="material"
	await studio.canvas._begin_paint(Vector2(32,32)); await studio.canvas._finish(Vector2(32,32))
	order_image=await output(); check(order_image.get_pixel(32,32).g>.02,"Later linked material covers intervening Color paint")
	studio.canvas.painting_mode="color"; studio.canvas.color=Color.BLUE
	await studio.canvas._begin_paint(Vector2(32,32)); await studio.canvas._finish(Vector2(32,32))
	order_image=await output(); check(order_image.get_pixel(32,32).b>.95 and order_image.get_pixel(32,32).r<.02,"Final Color paint remains on top of material stack")
	studio._action(func(): studio.document.create_live_material(Library.create("fabric/denim")))
	studio._select_live_material(studio.document.active_live_material_id); var remaining_id:=studio.document.active_live_material_id
	studio.canvas.painting_mode="material"; await studio.canvas._begin_paint(Vector2(70,32)); await studio.canvas._finish(Vector2(70,32))
	studio._select_live_material(order_template); await studio._bake_active_material()
	check(studio.document.live_material_for_id(remaining_id)!=null,"Baking one painted material preserves another template")
	studio._set_tool("eraser"); await studio.canvas._begin_paint(Vector2(32,32)); await studio.canvas._finish(Vector2(32,32))
	order_image=await output(); check(order_image.get_pixel(32,32).a<.05 and order_image.get_pixel(70,32).a>.9,"Eraser edits baked pixels with another live template on the same layer")
	studio.canvas.painting_mode="material"
	# Brush presets automatically switch mode and retain independent material copies.
	studio._set_tool("brush"); var material_preset:=studio._current_paint_preset("Oak Brush")
	studio.canvas.painting_mode="color"; studio._apply_paint_preset("brush",material_preset)
	check(studio.canvas.painting_mode=="material","Selecting Material preset automatically switches mode")
	studio.canvas.repair_tool.material.parameters.primary=Color.MAGENTA
	check(material_preset.material.parameters.primary!=Color.MAGENTA,"Editing active brush does not mutate saved preset")
	var color_preset:=studio._preset("Color",14,1,1,Color.BLUE); studio._apply_paint_preset("brush",color_preset)
	check(studio.canvas.painting_mode=="color" and studio.canvas.color==Color.BLUE,"Color preset automatically restores Color mode")
	studio._paint_presets.brush.append(material_preset); studio._preset_filter="material"; studio._refresh_context()
	var buttons:=studio.preset_context.find_children("*","Button",true,false); var found_material:=false
	for button in buttons:
		if button is KiwiImageWorkspace.PresetButton: found_material=true
	check(found_material,"Material filter displays material presets in unified bar")
	studio._paint_preset_menu("brush",material_preset)
	var popup: PopupMenu=studio.get_children().filter(func(node: Node): return node is PopupMenu)[-1]
	popup.id_pressed.emit(1); popup.hide()
	var duplicate: Dictionary=studio._paint_presets.brush[-1]
	check(duplicate.id!=material_preset.id and duplicate.material!=material_preset.material,"Duplicate creates independently editable material preset")
	studio._paint_preset_menu("brush",material_preset)
	popup=studio.get_children().filter(func(node: Node): return node is PopupMenu)[-1]; popup.id_pressed.emit(0); popup.hide()
	var rename: ConfirmationDialog=studio.get_children().filter(func(node: Node): return node is ConfirmationDialog)[-1]
	var name_input: LineEdit=rename.get_children().filter(func(node: Node): return node is LineEdit)[-1]
	name_input.text="Renamed material brush"; rename.confirmed.emit()
	check(material_preset.name=="Renamed material brush","Preset Rename action updates the named preset")
	studio._paint_preset_menu("brush",material_preset)
	popup=studio.get_children().filter(func(node: Node): return node is PopupMenu)[-1]; popup.id_pressed.emit(2); popup.hide()
	check(material_preset.get("favorite",false),"Preset Favorite action persists explicit favorite state")
	studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=false; studio.canvas.repair_tool.material=Library.create("wood/oak"); studio.canvas.color=Color.GREEN
	studio._set_tool("fill"); studio.canvas.painting_mode="color"; studio.canvas.color=Color.RED; studio.canvas.repair_tool.material=Library.create("stone/marble")
	studio._set_tool("brush")
	check(studio.canvas.painting_mode=="material" and studio.canvas.color==Color.GREEN and studio.canvas.repair_tool.material.material_id=="wood/oak","Brush remembers independent mode, solid color, and material")
	studio._set_tool("fill")
	check(studio.canvas.painting_mode=="color" and studio.canvas.color==Color.RED and studio.canvas.repair_tool.material.material_id=="stone/marble","Bucket remembers independent mode, solid color, and material")
	studio._set_tool("brush")
	var preset_path:="user://image_material_presets_test.tres"
	studio._paint_presets.brush.append(color_preset)
	studio._move_preset("brush",str(material_preset.id),str(color_preset.id))
	var ordered_ids:=[]
	for p in studio._paint_presets.brush: ordered_ids.append(p.id)
	studio._persist_paint_presets(preset_path)
	var restored_studio:=TestStudio.new(); root.add_child(restored_studio); restored_studio.hide(); restored_studio._load_paint_presets(preset_path)
	var restored_ids:=[]; var loaded_preset: Dictionary={}
	for p in restored_studio._paint_presets.brush:
		restored_ids.append(p.id)
		if p.id==material_preset.id: loaded_preset=p
	check(restored_ids==ordered_ids,"Unified preset order survives saving and restarting the workspace")
	check(loaded_preset.get("material") is KiwiTextureMaterial and loaded_preset.material.texture_size==material_preset.material.texture_size,"Material preset resource roundtrip retains procedural settings")
	check(loaded_preset.get("favorite",false) and loaded_preset.name=="Renamed material brush","Preset names and favorites survive restart")
	studio._delete_paint_preset("brush",str(color_preset.id))
	check(not studio._paint_presets.brush.any(func(p: Dictionary): return p.id==color_preset.id),"Delete removes only the selected brush preset")
	restored_studio.queue_free()
	studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=true; studio._refresh_context()
	preload("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(studio); await frames(20)
	var browser:=studio.get_node("MaterialBrowser")
	check(browser is PanelContainer and not browser is Window,"Material browser is a nonmodal dock")
	check(studio.canvas.is_visible_in_tree(),"Material editor leaves actual canvas visible")
	check(browser.settings_scroll.size.y>=120 and browser.settings_scroll.visible,"Dock reserves useful visible space for live material controls")
	browser._show_catalog(true); await frames(2); check(browser.catalog_panel.visible and not browser.settings_scroll.visible,"Narrow dock provides searchable material browser tab")
	browser._show_catalog(false); await frames(2)
	root.get_texture().get_image().save_png("res://.godot/verification/material_painting_ui.png")
	var remembered_material:=studio.canvas.repair_tool.material.copy_material()
	var mode:=studio.find_child("PaintingMode",true,false) as OptionButton; mode.item_selected.emit(0)
	check(studio.canvas.painting_mode=="color" and browser.is_closed(),"Color mode closes material-only dock settings")
	check(studio.canvas.repair_tool.material.material_id==remembered_material.material_id and studio.canvas.repair_tool.material.parameters==remembered_material.parameters,"Color mode keeps the last material settings independently")
	await frames(6); studio.queue_free(); await frames(6)
	print("Integrated material painting: %d checks, %d failures" % [checks,failures]); quit(failures)
