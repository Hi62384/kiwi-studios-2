extends SceneTree
class TestStudio extends KiwiImageWorkspace:
	func _persist_paint_presets(_path: String=PAINT_PRESETS_PATH) -> void: pass
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var failures:=0
var checks:=0
var studio: TestStudio
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func difference(a: Color,b: Color) -> float:
	return Vector4(a.r,a.g,a.b,a.a).distance_to(Vector4(b.r,b.g,b.b,b.a))
func frames(count:=5) -> void:
	for i in count: await process_frame
func source() -> Image:
	return Image.create(160,96,false,Image.FORMAT_RGBA8)
func setup(application: String) -> void:
	studio.open_source(ImageTexture.create_from_image(source())); studio._set_tool("brush")
	studio.canvas.painting_mode="material"; studio.document.live_edit_enabled=true; studio.canvas.paint_selection_only=false
	studio.canvas.brush_type="normal"; studio.canvas.brush_size=16; studio.canvas.hardness=1; studio.canvas.brush_opacity=1; studio.canvas.material_strength=1
	var material:=Library.create("wood/oak"); material.application=application; material.spacing=2.; material.texture_size=48
	material.jitter=.5; material.random_rotation=45.; material.random_scale=.2; material.follow_direction=true
	studio.canvas.repair_tool.material=material
func region() -> KiwiLivePaintRegion:
	return studio._main_layer().live_paint[-1]
func output() -> Image:
	studio.renderer.sync(studio.document); await frames(5)
	return await studio.renderer.source_image(studio._main_layer())
func draw() -> void:
	await studio.canvas._begin_paint(Vector2(24,48)); studio.canvas._paint_line(Vector2(24,48),Vector2(136,48)); await studio.canvas._finish(Vector2(136,48))
func run() -> void:
	root.size=Vector2i(1200,800); root.gui_embed_subwindows=true
	studio=TestStudio.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup("stamp"); studio.canvas.repair_tool.material.random_scale=0; await draw()
	check(region().coordinates!=null and region().coordinates.get_image().get_format()==Image.FORMAT_RGF,"Stamp brush stores editable float coordinates")
	check(region().coordinates.get_height()<48 and region().coordinate_rect.size.y<.5,"Committed coordinate maps crop to stroke bounds")
	var mask:=region().coverage.get_image()
	check(mask.get_pixel(24,48).a>.9 and mask.get_pixel(40,48).a<.05 and mask.get_pixel(56,48).a>.9,"Spacing produces distinct dabs through normal brush coverage")
	var before:=await output(); var template:=studio.document.live_material_for_id(studio.document.active_live_material_id)
	var changed:=template.material.copy_material(); changed.parameters.primary=Color.RED; changed.parameters.secondary=Color.YELLOW
	studio._material_changed(changed); studio._commit(); var after:=await output()
	check(difference(before.get_pixel(24,48),after.get_pixel(24,48))>.1,"Previously stamped artwork updates with template color")
	check(region().coverage.get_image().get_data()==mask.get_data(),"Stamp live edits preserve exact coverage")
	var material_id:=template.id; studio._select_live_material(material_id); await studio._bake_active_material(); var baked:=await output()
	check(difference(baked.get_pixel(24,48),after.get_pixel(24,48))<.035,"Baking keeps the coordinate-mapped stamp appearance")
	studio.undo(); check(region().coordinates!=null and studio.document.live_material_for_id(material_id)!=null,"Undo bake restores editable stamp coordinates")
	studio._set_tool("eraser"); studio.canvas.brush_opacity=.5
	await studio.canvas._begin_paint(Vector2(24,48)); var erasing:=await output()
	check(erasing.get_pixel(24,48).a>.48 and erasing.get_pixel(24,48).a<.52,"Live eraser preview updates before mouse release")
	studio.canvas._paint_line(Vector2(24,48),Vector2(24,48)); erasing=await output()
	check(erasing.get_pixel(24,48).a>.48 and erasing.get_pixel(24,48).a<.52,"Repeated eraser preview uses a fixed snapshot without cumulative opacity")
	await studio.canvas._finish(Vector2(24,48)); studio.undo(); erasing=await output()
	check(erasing.get_pixel(24,48).a>.95,"Undo restores live eraser coverage")
	setup("scatter"); await draw(); var scatter:=region().coverage.get_image().get_data(); var mapping:=region().coordinates.get_image().get_data()
	setup("scatter"); await draw()
	check(region().coverage.get_image().get_data()==scatter and region().coordinates.get_image().get_data()==mapping,"Scatter jitter and coordinate variation reproduce with the same seed")
	check(region().coverage.get_image().get_used_rect().size.y>16,"Scatter creates visible positional variation")
	# Normal selection and opacity processing remain shared with continuous brush.
	setup("stamp"); studio.canvas.brush_opacity=.5; studio.canvas.repair_tool.material.random_scale=0
	var selection:=source(); selection.fill_rect(Rect2i(0,0,32,96),Color(1,1,1,.5)); studio.document.pixel_selection=ImageTexture.create_from_image(selection)
	studio.document.pixel_selection_owner=studio._main_layer().id; studio.canvas.sync_pixel_selection(); studio.canvas.paint_selection_only=true
	await draw(); check(region().coverage.get_image().get_pixel(24,48).a>.24 and region().coverage.get_image().get_pixel(24,48).a<.26,"Stamped coverage respects opacity and fractional selection")
	check(region().coverage.get_image().get_pixel(56,48).a==0,"Stamped brush cannot escape pixel selection")
	setup("stamp"); studio.canvas.brush_type="stroke_correct"; studio.canvas.correction_strength=.7
	await studio.canvas._begin_paint(Vector2(24,48))
	for i in range(1,12):
		studio.canvas._corrector.add(Vector2(24+i*10,48+sin(i)*3),Time.get_ticks_usec()/1000000.0+float(i)*.02); studio.canvas._flush_corrected_stroke()
	await studio.canvas._finish(Vector2(136,48))
	check(region().coordinates!=null and region().coverage.get_image().get_used_rect().size.x>70,"Stroke Correct paints editable material stamps")
	setup("stamp"); studio.document.live_edit_enabled=false; await draw()
	check(studio.document.live_materials.is_empty() and studio._main_layer().texture.get_image().get_used_rect().has_area(),"Non-live stamps produce ordinary raster artwork")
	studio.queue_free(); await frames(6)
	print("Material stamp/scatter checks: %d checks, %d failures" % [checks,failures]); quit(failures)
