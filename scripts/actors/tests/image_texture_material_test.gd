extends SceneTree
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
const Render=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)
func run() -> void:
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio); studio.size=Vector2(1400,900)
	await process_frame; await process_frame
	studio._set_tool("repair"); studio.canvas.repair_tool.main_mode="texture"; studio._refresh_context()
	check(studio.find_child("RepairMode",true,false)!=null,"Two-mode toolbar loads and builds")
	load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(studio)
	var sheet:=Image.create(800,320,false,Image.FORMAT_RGBA8)
	var fingerprints: Dictionary={}; var index:=0
	for family in Library.CATEGORIES:
		var material:=Library.create(Library.ids().filter(func(id: String): return Library.category(id)==family)[0])
		material.blending="replace"
		var bitmap: Image=await Render.preview(root,material,Vector2i(160,160))
		check(bitmap.get_used_rect().has_area(),"Material renders: "+family)
		fingerprints[hash(bitmap.get_data())]=true
		sheet.blit_rect(bitmap,Rect2i(0,0,160,160),Vector2i(index%5*160,index/5*160)); index+=1
	check(fingerprints.size()==10,"Families render structurally different material images")
	sheet.save_png("res://.godot/material_family_contact_sheet.png")
	await catalog_sheet()
	await create_timer(2).timeout
	root.get_viewport().get_texture().get_image().save_png("res://.godot/material_browser_ui.png")
	var material:=Library.create("wood/oak"); var copy:=material.copy_material(); copy.parameters.density=3
	check(material.parameters.density!=copy.parameters.density,"Material instances own independent parameters")
	var saved_path:="res://.godot/material_roundtrip.tres"
	check(ResourceSaver.save(copy,saved_path)==OK,"Material resource saves")
	var restored:=ResourceLoader.load(saved_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTextureMaterial
	check(restored!=null and restored.parameters.density==3,"Material resource preserves settings")
	await application_checks()
	await integration(studio)
	studio.queue_free(); await process_frame; await process_frame
	print("Texture material checks: %d failures" % failures); quit(failures)

func wait_tool(tool: RefCounted) -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while (tool.active or tool.engine.busy()) and Time.get_ticks_msec()<deadline: await process_frame
	check(not tool.active,"Material gesture completes")

func catalog_sheet() -> void:
	var viewport:=SubViewport.new(); viewport.disable_3d=true; viewport.size=Vector2i(1300,1100); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var background:=ColorRect.new(); background.color=Color("13202b"); background.size=Vector2(viewport.size); viewport.add_child(background)
	var ids:=Library.ids(); check(ids.size()==143,"Catalog contains all 143 requested presets")
	for i in ids.size():
		var value:=Library.create(ids[i]); value.blending="replace"
		var tile:=ColorRect.new(); tile.position=Vector2((i%13)*100,(i/13)*100); tile.size=Vector2(96,76); tile.material=Render.material(value,tile.size); viewport.add_child(tile)
		var caption:=Label.new(); caption.text=value.label; caption.position=tile.position+Vector2(0,76); caption.size=Vector2(96,22); caption.clip_text=true; caption.add_theme_font_size_override("font_size",9); viewport.add_child(caption)
	for i in 4: await RenderingServer.frame_post_draw
	var bitmap:=viewport.get_texture().get_image(); bitmap.save_png("res://.godot/material_catalog_contact_sheet.png")
	for i in ids.size():
		var area:=Rect2i((i%13)*100,(i/13)*100,96,76)
		check(bitmap.get_region(area).get_data()!=Image.create(96,76,false,Image.FORMAT_RGBA8).get_data(),"Preset renders: "+ids[i])
	viewport.queue_free()
	var image:=Image.create(64,32,false,Image.FORMAT_RGBA8); image.fill(Color.RED); image.fill_rect(Rect2i(32,0,32,32),Color(0,0,1,.5))
	image.generate_mipmaps()
	var imported:=Library.create("geometry/checkerboard"); imported.image=ImageTexture.create_from_image(image); imported.texture_size=32
	var preview:=await Render.preview(root,imported,Vector2i(64,32))
	check(preview.get_pixel(16,16).r>.9 and preview.get_pixel(48,16).b>.9,"Imported image preserves a 2:1 aspect ratio")
	check(absf(preview.get_pixel(48,16).a-.5)<.01,"Imported image preserves partial alpha")
	var wood:=Library.create("wood/oak"); var first:=await Render.preview(root,wood)
	wood.texture_size*=2; var second:=await Render.preview(root,wood)
	check(first.get_data()!=second.get_data(),"Independent texture size changes rendered detail scale")
	wood.relief=1; var embossed:=await Render.preview(root,wood)
	check(embossed.get_data()!=second.get_data(),"Relief lighting alters material shading")

func integration(studio: KiwiImageWorkspace) -> void:
	var browser:=studio.get_node_or_null("MaterialBrowser")
	if browser!=null: browser.close()
	await process_frame
	var bitmap:=Image.create(96,96,false,Image.FORMAT_RGBA8); bitmap.fill(Color(.25,.35,.45))
	studio.open_source(ImageTexture.create_from_image(bitmap)); studio._set_tool("repair")
	var tool=studio.canvas.repair_tool; tool.main_mode="texture"; tool.choose_material("wood/oak"); tool.mode="pattern_fill"; tool.config.selection_only=false; tool.config.hardness=1.; tool.config.size=24.; tool.config.opacity=.5
	var original:=studio._main_layer(); var history:=studio._undo.size()
	tool.begin(original,Vector2(48,48)); tool.process(); tool.finish(); await wait_tool(tool)
	check(studio.document.layers.size()==2,"Texture paint creates an independent editable material layer")
	var layer:=studio._main_layer(); var value: KiwiTextureMaterial=layer.properties.get("texture_material")
	check(value!=null and absf(value.coverage.get_image().get_pixel(48,48).a-.5)<.01,"Material strokes store fractional opacity as coverage")
	check(value.coverage.get_image().get_pixel(0,0).a==0,"Unpainted material pixels remain transparent")
	check(original.texture.get_image().get_data()==bitmap.get_data(),"Material paint leaves original pixels unchanged")
	check(studio._undo.size()==history+1,"A material stroke is one undo action")
	studio.undo(); check(studio.document.layers.size()==1,"Undo removes the new material layer")
	studio.redo(); layer=studio.document.layers[-1]; studio.canvas.selected.assign([layer.id])
	check(layer.properties.texture_material.coverage!=null,"Redo restores material coverage")
	tool.material=layer.properties.texture_material.copy_material(); var old_color: Color=tool.material.parameters.primary
	tool.material.parameters.primary=Color.RED; tool.apply_material_settings(true); tool.material.parameters.primary=Color.GREEN; tool.apply_material_settings(true); studio._commit()
	check(studio._undo.size()==history+2,"Multiple live material previews commit as one edit")
	studio.undo(); layer=studio.document.layers[-1]; check(layer.properties.texture_material.parameters.primary==old_color,"Undo restores edited material parameters")
	studio.redo(); layer=studio.document.layers[-1]; studio.canvas.selected.assign([layer.id]); value=layer.properties.texture_material
	load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(studio)
	var editor:=studio.get_node("MaterialBrowser"); var contrast: SpinBox
	for label in editor.fields.find_children("*","Label",true,false):
		if label.text=="Contrast": contrast=label.get_parent().get_child(1)
	check(contrast!=null,"Material browser includes precise numeric controls")
	if contrast!=null:
		var count:=studio._undo.size(); contrast._begin_drag(Vector2.ZERO); contrast.dragging=true; contrast.drag_pixels(8,false,false); contrast.drag_pixels(8,false,false)
		check(studio._undo.size()==count,"Dragging material controls previews without adding history")
		contrast.finish_drag(); check(studio._undo.size()==count+1,"Releasing a material control commits one undo action")
		studio.undo(); check(is_equal_approx(studio.document.layers[-1].properties.texture_material.parameters.contrast,1.),"Browser refreshes its material instance after undo")
	editor.close(); await process_frame; layer=studio.document.layers[-1]; studio.canvas.selected.assign([layer.id]); value=layer.properties.texture_material
	var painted:=await Render.preview(root,value,Vector2i(96,96)); check(painted.get_pixel(48,48).g>0 and painted.get_pixel(0,0).a==0,"Material preview uses editable coverage and current parameters")
	value.secondary=Library.create("geometry/checkerboard"); value.mix_amount=1
	var mixed:=await Render.preview(root,value,Vector2i(96,96)); check(mixed.get_data()!=painted.get_data(),"Mixer evaluates a structurally independent second material")
	var path:="res://.godot/painted_material_document.tres"; ResourceSaver.save(studio.document,path)
	var document:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(document.layers[-1].properties.texture_material.secondary!=null and document.layers[-1].properties.texture_material.coverage.get_image().get_data()==value.coverage.get_image().get_data(),"Native documents preserve material, mixer and coverage")
	studio.renderer.sync(studio.document); var exported:=await studio.renderer.flattened()
	check(exported!=null and exported.get_pixel(48,48)!=bitmap.get_pixel(48,48),"Export renders non-destructive material layers")
	layer.dimensions=Vector2(192,96)
	var selection:=Image.create(192,96,false,Image.FORMAT_RGBA8); selection.fill_rect(Rect2i(0,0,48,96),Color(1,1,1,.5))
	studio.document.pixel_selection=ImageTexture.create_from_image(selection); studio.document.pixel_selection_owner=layer.id; studio.canvas.sync_pixel_selection()
	tool.material=value.copy_material(); tool.config.opacity=1; await tool.fill_selection(); tool.finish(); await wait_tool(tool)
	check(absf(studio._main_layer().properties.texture_material.coverage.get_image().get_pixel(12,12).a-.5)<.02,"Fill selection scales a fractional mask into resized-layer pixel coordinates")
	await studio.rasterize_selected(); check(not studio._main_layer().properties.has("texture_material"),"Bake turns a material into ordinary pixels")
	studio.undo(); check(studio.document.layers[-1].properties.get("texture_material") is KiwiTextureMaterial,"Bake is undoable")

func application_checks() -> void:
	var engine:=preload("res://Workspaces/ImageWorkspace/image_repair_engine.gd").new()
	var source:=Image.create(32,32,false,Image.FORMAT_RGBA8); source.fill(Color.RED)
	var original:=Image.create(64,64,false,Image.FORMAT_RGBA8); original.fill(Color.BLUE)
	var settings:={"size":24.,"hardness":1.,"strength":1.,"opacity":1.,"application":"stamp","sample_mode":"current","selection_only":false,"seed":17}
	var job:={"generation":0,"kind":"pattern_fill","original":original,"sample":source,"settings":settings,"area":Rect2i(0,0,64,64),"source_area":Rect2i(0,0,32,32),"source_anchor":Vector2.ZERO,"destination_anchor":Vector2.ZERO,"points":PackedVector2Array([Vector2(32,32)]),"fill":false}
	var result: Dictionary=engine._work(job)
	check(result.image.get_pixel(32,32).r>.95 and result.image.get_pixel(0,0).b>.95,"Stamp paints its footprint and leaves surroundings untouched")
	settings.application="scatter"; settings.jitter=.5
	var scattered: Dictionary=engine._work(job)
	check(scattered.image.get_data()!=result.image.get_data(),"Scatter applies deterministic positional variation")
	check(scattered.image.get_data()==engine._work(job).image.get_data(),"Scatter results are reproducible")
	for diameter in [64,256,1024]:
		var base:=Image.create(diameter,diameter,false,Image.FORMAT_RGBA8)
		var benchmark:=job.duplicate(); benchmark.original=base; benchmark.prior_coverage=base; benchmark.editable_texture=true; benchmark.area=Rect2i(Vector2i.ZERO,base.get_size()); benchmark.points=PackedVector2Array([Vector2.ONE*diameter*.5]); benchmark.settings=settings.duplicate(); benchmark.settings.application="continuous"; benchmark.settings.size=float(diameter); benchmark.settings.opacity=.5
		var start:=Time.get_ticks_usec(); var output:=engine._work(benchmark)
		print("Editable material %dpx brush CPU: %.1f ms" % [diameter,(Time.get_ticks_usec()-start)/1000.0])
		check(absf(output.coverage.get_pixel(diameter/2,diameter/2).a-.5)<.01,"Large material brush preserves its opacity")
	engine.free()
