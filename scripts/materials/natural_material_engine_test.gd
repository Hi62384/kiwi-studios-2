extends SceneTree
const MaterialEngine=preload("res://scripts/materials/natural_material_engine.gd")
const Definitions=preload("res://scripts/materials/natural_material_definitions.gd")
const Renderer=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
const Presets=preload("res://scripts/materials/natural_material_presets.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(condition: bool,message: String) -> void:
	if not condition: failures+=1;push_error(message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/verification")
	check(preload("res://scripts/materials/natural_material_shader_source.gd").source==FileAccess.get_file_as_string("res://scripts/materials/natural_material_pattern.gdshaderinc"),"Exported ShaderInclude is byte-equivalent to development source")
	check(Definitions.ids().size()==143,"All legacy IDs preserved")
	for id in Definitions.ids():
		var material:=Definitions.create(id)
		check(MaterialEngine.normalize(MaterialEngine.settings_from_material(material)).material_id==id,"Settings roundtrip: "+id)
		for parameter in Definitions.schema(id): check(material.parameters.has(parameter.key),"Schema key: "+id)
	var sample:=Definitions.create("wood/oak")
	var copy:=sample.copy_material();copy.parameters.primary=Color.RED
	check(sample.parameters.primary!=copy.parameters.primary,"Copies have independent parameters")
	var imported_sample:=copy.copy_material();imported_sample.image=ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGBA8));imported_sample.secondary=Definitions.create("geometry/checkerboard");imported_sample.mix_amount=.4
	var adapted:=MaterialEngine.material_from_settings(MaterialEngine.settings_from_material(imported_sample))
	check(adapted.image==imported_sample.image and adapted.secondary!=null and adapted.secondary.material_id=="geometry/checkerboard" and adapted.mix_amount==.4,"Scene settings preserve imported image and material mixer")
	var preset:=Presets.save_material(copy)
	check(not preset.is_empty(),"Shared preset saves")
	var loaded:=Presets.load_material(preset)
	check(loaded!=null and loaded.parameters.primary==Color.RED,"Shared preset roundtrip")
	if loaded!=null:
		loaded.parameters.primary=Color.BLUE
		check(Presets.load_material(preset).parameters.primary==Color.RED,"Editing instance never mutates preset")
	Presets.remove(preset)
	if DisplayServer.get_name()=="headless":
		print("Natural Material data checks: %d failures; GPU tests require display renderer" % failures);quit(failures);return
	if OS.get_cmdline_user_args().has("--compatibility-only"):
		await compatibility_checks();print("Natural Material coverage/mixer/import checks: %d failures" % failures);quit(failures);return
	await render_catalog()
	await parameter_checks()
	await tiling_checks()
	await compatibility_checks()
	var start:=Time.get_ticks_usec()
	var maps:=await MaterialEngine.render_maps(root,sample,Vector2i(256,256),["albedo","height","normal","roughness","metallic"])
	check(maps.size()==5,"All requested output channels render")
	print("Five 256px output maps: %.2f ms (includes three GPU frames per channel)" % ((Time.get_ticks_usec()-start)/1000.))
	for key in maps: maps[key].save_png("res://.godot/verification/natural_wood_"+key+".png")
	start=Time.get_ticks_usec()
	var cached:=await MaterialEngine.render_maps(root,sample,Vector2i(256,256),["albedo"])
	check(cached.albedo.get_data()==maps.albedo.get_data(),"Cached deterministic albedo")
	print("Cached 256px output: %.2f ms" % ((Time.get_ticks_usec()-start)/1000.))
	var uncached:=await Renderer.preview(root,sample,Vector2i(256,256))
	var repeat:=await Renderer.preview(root,sample,Vector2i(256,256))
	check(uncached.get_data()==repeat.get_data(),"Identical parameters and seed produce identical GPU pixels")
	var original:=sample.copy_material();sample.texture_size*=2
	check((await Renderer.preview(root,sample,Vector2i(256,256))).get_data()!=uncached.get_data(),"Texture size changes structure independently of coverage")
	original.relief=.8
	var embossed:=await Renderer.preview(root,original,Vector2i(256,256))
	check(embossed.get_data()!=uncached.get_data(),"Height-derived emboss changes appearance")
	original.light_direction+=180
	check((await Renderer.preview(root,original,Vector2i(256,256))).get_data()!=embossed.get_data(),"Emboss responds to light direction")
	await spatial_check()
	print("Natural Material engine: %d failures" % failures);quit(failures)

func render_catalog() -> void:
	var viewport:=SubViewport.new();viewport.disable_3d=true;viewport.size=Vector2i(1430,1232);viewport.transparent_bg=false;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var background:=ColorRect.new();background.size=Vector2(viewport.size);background.color=Color("151d24");viewport.add_child(background)
	var ids:=Definitions.ids()
	for i in ids.size():
		var value:=Definitions.create(ids[i]);value.blending="replace"
		var rect:=ColorRect.new();rect.position=Vector2(i%13*110,i/13*112);rect.size=Vector2(108,92);rect.material=Renderer.material(value,Vector2(256,256));viewport.add_child(rect)
		var caption:=Label.new();caption.text=value.label;caption.position=rect.position+Vector2(0,92);caption.add_theme_font_size_override("font_size",10);viewport.add_child(caption)
	for frame in 6: await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image();image.save_png("res://.godot/verification/natural_material_catalog.png")
	var hashes: Dictionary={}
	for i in ids.size():
		var tile:=image.get_region(Rect2i(i%13*110,i/13*112,108,92));hashes[hash(tile.get_data())]=ids[i]
		check(tile.get_pixel(30,30)!=Color.MAGENTA,"Material renders: "+ids[i])
	print("Catalog renders %d presets, %d distinct pixel fingerprints" % [ids.size(),hashes.size()])
	check(hashes.size()>130,"Catalog presets retain distinct appearance")
	viewport.queue_free()
	for family in Definitions.CATEGORIES:
		var family_ids:=ids.filter(func(id: String): return Definitions.category(id)==family)
		var sheet:=Image.create(256*4,256*ceili(family_ids.size()/4.),false,Image.FORMAT_RGBA8)
		for i in family_ids.size():
			var bitmap:=await Renderer.preview(root,Definitions.create(family_ids[i]),Vector2i(240,240),Vector2(256,256))
			sheet.blit_rect(bitmap,Rect2i(0,0,240,240),Vector2i(i%4*256,i/4*256))
		check(sheet.save_png("res://.godot/verification/natural_"+family.to_lower()+"_family.png")==OK,"Family sheet saved")

func parameter_checks() -> void:
	var insensitive: Array[String]=[]
	for id in Definitions.ids():
		for parameter in Definitions.schema(id):
			if parameter.key=="roughness": continue # A physical lighting response, verified by spatial output.
			var value:=Definitions.create(id);value.parameters[parameter.key]=parameter.min
			var low:=await Renderer.preview(root,value,Vector2i(111,111),Vector2(256,256))
			value.parameters[parameter.key]=parameter.max
			var high:=await Renderer.preview(root,value,Vector2i(111,111),Vector2(256,256))
			if low.get_data()==high.get_data(): insensitive.append(id+":"+parameter.key)
	print("Inactive exposed parameters: ",insensitive)
	check(insensitive.is_empty(),"Every exposed structure control changes real output")

func tiling_checks() -> void:
	for id in ["wood/oak","metal/hammered_metal","fabric/denim","stone/marble","ground/gravel","illustration/crosshatching","noise/simplex_noise"]:
		var value:=Definitions.create(id);value.relief=0.
		var image:=await Renderer.preview(root,value,Vector2i(256,128),Vector2(value.texture_size*2.,value.texture_size))
		var first:=image.get_region(Rect2i(0,0,128,128)).get_data()
		var second:=image.get_region(Rect2i(128,0,128,128)).get_data()
		var total:=0.;var largest:=0
		for index in first.size():
			var difference:=absi(first[index]-second[index]);total+=difference;largest=maxi(largest,difference)
		print("Periodic repeats %s: mean %.5f/255, max %d/255" % [id,total/first.size(),largest])
		check(total/first.size()<.05,"Seamless repeat pixels match: "+id)

func compatibility_checks() -> void:
	var value:=Definitions.create("wood/oak")
	var plain:=await Renderer.preview(root,value,Vector2i(128,128))
	value.secondary=Definitions.create("geometry/checkerboard");value.mix_amount=1.
	var mixed:=await Renderer.preview(root,value,Vector2i(128,128))
	check(mixed.get_data()!=plain.get_data(),"Specialized legacy mixer renders independent second family")
	value.mix_amount=0.
	check((await Renderer.preview(root,value,Vector2i(128,128))).get_data()==plain.get_data(),"Disabled mixer preserves original output")
	var imported:=Image.create(64,32,false,Image.FORMAT_RGBA8);imported.fill(Color.RED);imported.fill_rect(Rect2i(32,0,32,32),Color(0,0,1,.5))
	value=Definitions.create("geometry/checkerboard");value.image=ImageTexture.create_from_image(imported);value.texture_size=32
	var bitmap:=await Renderer.preview(root,value,Vector2i(64,32))
	check(bitmap.get_pixel(16,16).r>.9 and bitmap.get_pixel(48,16).b>.9,"Imported image preserves aspect ratio")
	check(absf(bitmap.get_pixel(48,16).a-.5)<.01,"Imported image preserves partial alpha")
	var coverage:=Image.create(64,32,false,Image.FORMAT_RGBA8);coverage.fill_rect(Rect2i(0,0,32,32),Color(1,1,1,.5));value.coverage=ImageTexture.create_from_image(coverage)
	bitmap=await Renderer.preview(root,value,Vector2i(64,32))
	check(absf(bitmap.get_pixel(16,16).a-.5)<.01 and bitmap.get_pixel(48,16).a==0.,"Coverage multiplies alpha without tinting or darkening")
	await coordinate_checks()

func coordinate_checks() -> void:
	var value:=Definitions.create("wood/oak");value.alignment="canvas"
	var size:=Vector2i(64,64);var coordinates:=Image.create(64,64,false,Image.FORMAT_RGF)
	for y in 64:
		for x in 64: coordinates.set_pixel(x,y,Color(x+.5,y+.5,0.,1.))
	var original:=await Renderer.preview(root,value,size)
	var mapped:=await Renderer.preview(root,value,size,Vector2(size),Transform2D.IDENTITY,ImageTexture.create_from_image(coordinates))
	check(mapped.get_data()==original.get_data(),"Identity float coordinate map preserves rendered material")
	var offset:=Vector2(12,5)
	for y in 64:
		for x in 64: coordinates.set_pixel(x,y,Color(x+.5+offset.x,y+.5+offset.y,0.,1.))
	var coordinate_texture:=ImageTexture.create_from_image(coordinates)
	mapped=await Renderer.preview(root,value,size,Vector2(size),Transform2D.IDENTITY,coordinate_texture)
	var shifted:=await Renderer.preview(root,value,size,Vector2(size),Transform2D(0.,offset))
	check(mapped.get_data()!=original.get_data(),"Stamp coordinate map changes placement without modifying the generator")
	check(mapped.get_data()==shifted.get_data(),"Stamp pixel coordinates agree with ordinary material mapping")
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8);mask.fill_rect(Rect2i(16,16,32,32),Color.WHITE);value.coverage=ImageTexture.create_from_image(mask)
	var full:=await Renderer.preview(root,value,size,Vector2(size),Transform2D.IDENTITY,coordinate_texture)
	var cropped:=ImageTexture.create_from_image(coordinates.get_region(Rect2i(16,16,32,32)))
	var cropped_preview:=await Renderer.preview(root,value,size,Vector2(size),Transform2D.IDENTITY,cropped,Rect2(.25,.25,.5,.5))
	check(cropped_preview.get_data()==full.get_data(),"Cropped coordinate maps preserve exact covered pixels for baking")

func spatial_check() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(640,320);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.position=Vector3(0,.8,3.2);camera.fov=35;viewport.add_child(camera);camera.look_at(Vector3.ZERO)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-25,0);light.light_energy=2.;viewport.add_child(light)
	for i in 2:
		var mesh:=MeshInstance3D.new();mesh.mesh=SphereMesh.new();mesh.scale=Vector3.ONE*1.6;mesh.position.x=-.7+i*1.4
		var settings:=MaterialEngine.defaults("wood/oak" if i==0 else "metal/hammered_metal");settings.relief=.6;settings.mapping="uv" if i==0 else "triplanar"
		mesh.material_override=MaterialEngine.create_spatial_material(settings);viewport.add_child(mesh)
	for frame in 8: await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image();image.save_png("res://.godot/verification/natural_spatial.png")
	check(image.get_pixel(200,160)!=image.get_pixel(0,0),"Spatial materials render actual mesh surfaces")
	var first_mesh:=viewport.get_child(2) as MeshInstance3D
	var mixture:=Definitions.create("wood/oak");mixture.secondary=Definitions.create("geometry/checkerboard");mixture.mix_amount=.8
	first_mesh.material_override=MaterialEngine.spatial_material(mixture)
	for frame in 4: await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_data()!=image.get_data(),"Spatial material compiles and renders shared secondary mixer")
	viewport.queue_free()
