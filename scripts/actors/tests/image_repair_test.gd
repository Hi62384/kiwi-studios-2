extends SceneTree
const EngineScript=preload("res://Workspaces/ImageWorkspace/image_repair_engine.gd")
const Synthesis=preload("res://Workspaces/ImageWorkspace/image_texture_synthesis.gd")
const Generator=preload("res://Workspaces/ImageWorkspace/image_procedural_texture.gd")
const Alpha=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func settings() -> Dictionary:
	return {"size":16.0,"hardness":1.0,"strength":1.0,"opacity":1.0,"patch_size":8,"quality":1,"seed":42,"selection_only":true,"source_mode":"manual","sample_shape":"rectangle","search_radius":6}
func job(mode: String,original: Image,source: Image) -> Dictionary:
	return {"generation":0,"kind":mode,"original":original,"sample":source,"settings":settings(),"area":Rect2i(0,0,32,32),"source_area":Rect2i(Vector2i.ZERO,source.get_size()),"source_anchor":Vector2(16,16),"destination_anchor":Vector2(16,16),"points":PackedVector2Array([Vector2(16,16)]),"fill":true}
func run() -> void:
	var engine:=EngineScript.new()
	var blue:=Image.create(32,32,false,Image.FORMAT_RGBA8); blue.fill(Color.BLUE)
	var red:=Image.create(32,32,false,Image.FORMAT_RGBA8); red.fill(Color.RED)
	var input:=job("clone",blue,red)
	var partial:=Image.create(32,32,false,Image.FORMAT_RGBA8); partial.fill_rect(Rect2i(8,8,16,16),Color(1,1,1,.5))
	input.selection=partial
	var result: Dictionary=engine._work(input)
	check(absf(result.image.get_pixel(16,16).r-.5)<.006 and absf(result.image.get_pixel(16,16).b-.5)<.006,"Clone lerps by fractional selection alpha")
	check(result.image.get_pixel(0,0)==Color.BLUE,"Clone leaves unselected pixels untouched")
	check(red.get_pixel(16,16)==Color.RED and blue.get_pixel(16,16)==Color.BLUE,"Repair never mutates source snapshots")
	var outside:=job("clone",blue,red); outside.source_anchor=Vector2(-1000,-1000)
	check(engine._work(outside).image.get_data()==blue.get_data(),"An invalid clone source leaves existing pixels intact")
	var transformed:=job("clone",blue,red)
	var reference:=KiwiImageLayer.create("basic",Vector2i(32,32)); reference.properties.yaw_left_right=30.0
	transformed.reference=reference; transformed.frame=Transform2D(.2,Vector2(8,4))
	var world_mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); world_mask.fill_rect(Rect2i(16,8,30,30),Color(1,1,1,.5)); transformed.selection=world_mask
	result=engine._work(transformed)
	check(result.image.get_pixel(0,0)==Color.BLUE and absf(result.image.get_pixel(16,16).r-.5)<.01,"Repair maps partial selections through layer translation, rotation and yaw")
	input.settings.new_layer=true; result=engine._work(input)
	check(absf(result.image.get_pixel(16,16).a-.5)<.005,"New repair layer retains fractional coverage")
	var blank:=Image.create(32,32,false,Image.FORMAT_RGBA8); blank.fill(Color.TRANSPARENT)
	result=engine._work(job("clone",blue,blank)); check(result.image.get_pixel(16,16).a==0,"Clone copies source transparency without dark halos")
	var heal:=job("heal",blue,red); heal.settings.healing_blend="texture"
	result=engine._work(heal)
	# A surrounding blue border provides the low frequency target tone.
	heal.area=Rect2i(8,8,16,16); result=engine._work(heal)
	check(result.image.get_pixel(8,8).b>.95,"Healing adapts source color to surrounding destination tone")
	var smooth:=Image.create(64,64,false,Image.FORMAT_RGBA8); smooth.fill(Color(.6,.5,.4))
	smooth.fill_rect(Rect2i(30,30,4,4),Color.BLACK)
	var spot:=job("spot",smooth,smooth); spot.area=Rect2i(26,26,12,12); spot.automatic=true
	result=engine._work(spot)
	check(result.image.get_pixel(6,6).r>.5,"Spot Heal removes a dark blemish using clean neighboring detail")
	var source:=Image.create(24,24,false,Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24: source.set_pixel(x,y,Color(float((x*17+y*11)%19)/19,float((x+y)%3)/3,.4,1))
	var target:=Image.create(64,64,false,Image.FORMAT_RGBA8); target.fill(Color(.4,.4,.4))
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); mask.fill(Color.WHITE)
	var start:=Time.get_ticks_usec()
	var synthesized:=Synthesis.synthesize(target,source,Rect2i(0,0,24,24),mask,settings())
	print("64px quilting CPU: %.1f ms" % ((Time.get_ticks_usec()-start)/1000.0))
	check(synthesized.get_data()==Synthesis.synthesize(target,source,Rect2i(0,0,24,24),mask,settings()).get_data(),"Synthesis is deterministic for the same seed")
	check(synthesized.get_pixel(60,60)!=target.get_pixel(60,60),"Pattern Heal extends a small source over a larger area")
	check(not Synthesis.valid_patch(Vector2i.ZERO,Vector2i(8,8),Rect2i(0,0,24,24),{"sample_shape":"circle"}),"Circle sources reject patches outside their source mask")
	var fill=preload("res://Workspaces/ImageWorkspace/image_pattern_fill.gd")
	check(fill.sample(source,Rect2i(0,0,24,24),Vector2(27,2),{})==source.get_pixel(3,2),"Exact repeat keeps the source detail without stretching")
	check(fill.sample(source,Rect2i(0,0,24,24),Vector2(6,4),{"scale":2.0})==source.get_pixel(3,2),"Pattern scale adjusts repetition size")
	check(fill.sample(source,Rect2i(0,0,24,24),Vector2(27,2),{"spacing":1.0}).a==0,"Pattern spacing leaves gaps")
	var patch:=job("patch",blue,red); patch.selection=partial; patch.settings.patch_size=8
	result=engine._work(patch)
	check(result.image.get_pixel(0,0)==Color.BLUE and absf(result.image.get_pixel(16,16).r-.5)<.01,"Patch repair clips its multiple source patches to fractional selections")
	var tiny:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	check(Synthesis.synthesize(target,tiny,Rect2i(0,0,1,1),mask,settings()).get_data()==target.get_data(),"Insufficient samples leave the destination unchanged")
	var recipe:=KiwiImageTextureRecipe.new()
	var noise:=Generator.generate(recipe,Vector2i(48,32))
	check(noise.get_data()==Generator.generate(recipe,Vector2i(48,32)).get_data(),"Procedural recipes are reproducible")
	for y in 32: check(noise.get_pixel(0,y)==noise.get_pixel(47,y),"Procedural X border tiles exactly")
	for x in 48: check(noise.get_pixel(x,0)==noise.get_pixel(x,31),"Procedural Y border tiles exactly")
	recipe.settings.seed=17; check(noise.get_data()!=Generator.generate(recipe,Vector2i(48,32)).get_data(),"Seed changes the generated texture")
	for category in Generator.TYPES:
		for kind in Generator.TYPES[category]:
			recipe.kind=kind; var generated:=Generator.generate(recipe,Vector2i(16,16))
			check(generated.get_size()==Vector2i(16,16) and generated.get_pixel(0,4)==generated.get_pixel(15,4),"Every procedural preset generates a tileable texture: "+kind)
	var stamp:=Alpha.stamp(32,.8)
	check(stamp.get_pixel(16,16).a>.99 and stamp.get_pixel(3,16).a>0 and stamp.get_pixel(3,16).a<.8,"Selection falloff creates partial coverage")
	var zero:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	var selected:=Alpha.blend(zero,stamp,.5,false)
	check(absf(selected.get_pixel(16,16).a-.5)<.005,"Alpha limits selected pixel coverage")
	check(Alpha.blend(selected,stamp,1,true).get_pixel(16,16).a<.005,"Selection erasing removes coverage")
	engine.free()
	if DisplayServer.get_name()!="headless": await integration()
	print("Texture / repair / fractional mask checks: %d failures" % failures); quit(failures)

func wait_repair(tool: RefCounted) -> void:
	var timeout:=Time.get_ticks_msec()+20000
	while (tool.active or tool.engine.busy()) and Time.get_ticks_msec()<timeout: await process_frame
	check(not tool.active,"Worker finishes a repair gesture")

func integration() -> void:
	root.size=Vector2i(1400,850)
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8); image.fill(Color.BLUE)
	studio.open_source(ImageTexture.create_from_image(image)); studio._set_tool("repair")
	for i in 4: await process_frame
	var tool=studio.canvas.repair_tool; tool.mode="clone"; tool.main_mode="repair"; tool.repair_source="sample"; tool.repair_method="exact"
	studio._refresh_context()
	var mode_picker:=studio.find_child("RepairMode",true,false) as MenuButton
	check(mode_picker!=null and mode_picker.get_popup().item_count==3,"Texture and repair expose only two main modes")
	var icon_signatures: Dictionary={}
	for i in range(1,mode_picker.get_popup().item_count): icon_signatures[hash(mode_picker.get_popup().get_item_icon(i).get_image().get_data())]=true
	check(icon_signatures.size()==2,"Both main modes have distinct icons")
	var sample_button: Button
	for node in studio.find_children("*","Button",true,false):
		if node.text=="Sample source": sample_button=node
	check(sample_button!=null,"Repair exposes an explicit Sample Source action")
	if sample_button!=null:
		sample_button.pressed.emit()
		check(tool.pick_source,"Sample Source arms the next canvas click")
		var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=tool.to_screen(Vector2(8,8),studio._main_layer())
		tool.handle(press); press.pressed=false; tool.handle(press)
		check(tool.source_image!=null and tool.source_point.distance_to(Vector2(8,8))<.001,"Clicking Sample Source preserves the exact clicked anchor without shifting to the sample box center")
	tool.source_image=image.duplicate(); tool.source_image.fill(Color.RED); tool.source_point=Vector2(32,32); tool.source_area=Rect2i(0,0,64,64)
	tool.config.hardness=1; tool.config.size=20.0; tool.config.selection_only=false
	tool.begin(studio._main_layer(),Vector2(32,32)); tool.process()
	for i in 10: await process_frame
	check(studio._main_layer().texture.get_image().get_pixel(32,32).r>.95,"Repair renders live before mouse release")
	check(studio._undo.is_empty(),"Live repair preview does not create undo entries")
	tool.finish(); await wait_repair(tool)
	check(studio._undo.size()==1,"One completed repair creates one undo action")
	studio.undo(); check(studio._main_layer().texture.get_image().get_pixel(32,32).b>.95,"Repair undo restores pixels")
	studio.redo(); check(studio._main_layer().texture.get_image().get_pixel(32,32).r>.95,"Repair redo restores result")
	tool.begin(studio._main_layer(),Vector2(16,16)); tool.process(); tool.cancel()
	for i in 5: await process_frame
	check(studio._main_layer().texture.get_image().get_pixel(16,16).b>.95,"Cancellation rejects stale repair worker results")
	tool.config.new_layer=true; tool.begin(studio._main_layer(),Vector2(16,16)); tool.finish(); await wait_repair(tool)
	check(studio.document.layers.size()==2,"Repair on a separate layer leaves the original intact")
	studio.undo(); check(studio.document.layers.size()==1,"New repair layer creation undoes with its pixels")
	studio.canvas.selected.assign([studio.document.layers[0].id])
	tool.config.new_layer=false
	# Selections can be previewed, altered, cancelled, then explicitly applied.
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(4,4,16,16),Color(1,1,1,.5))
	studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=studio._main_layer().id; studio.canvas.sync_pixel_selection()
	tool.config.selection_only=true; var history:=studio._undo.size()
	await tool.fill_selection()
	while tool.engine.busy(): await process_frame
	check(tool.active and tool.selection_preview and studio._undo.size()==history,"Selection preview stays editable without committing history")
	tool.configure("opacity",.2)
	while tool.engine.busy(): await process_frame
	check(studio._main_layer().texture.get_image().get_pixel(8,8).r<.15,"Selection preview updates its opacity live without accumulation")
	tool.cancel(); check(studio._main_layer().texture.get_image().get_pixel(8,8).b>.95,"Selection preview cancellation restores original pixels")
	tool.config.opacity=1; await tool.fill_selection(); tool.finish(); await wait_repair(tool)
	check(studio._undo.size()==history+1,"Apply commits one selection-repair action")
	studio.undo()
	tool.mode="patch"; tool.config.source_mode="manual"; tool.begin_patch_source(Vector2(8,8),studio._main_layer())
	var drag:=InputEventMouseMotion.new(); drag.position=studio.canvas.origin()+Vector2(28,8)*studio.canvas.zoom
	tool.handle(drag)
	check(tool.source_area.position.x>=24,"Patch source dragging moves the selected region's source footprint")
	tool.sampling=false; tool._patch_drag=false; tool.mode="clone"; tool.source_point=Vector2(32,32); tool.source_image=image.duplicate(); tool.source_image.fill(Color.RED)
	# Finish a running stroke before switching tools, rather than losing it.
	tool.config.selection_only=false; tool.begin(studio._main_layer(),Vector2(8,8)); tool.process(); studio._set_tool("move")
	await wait_repair(tool)
	for i in 3: await process_frame
	check(studio.canvas.tool=="move" and studio._main_layer().texture.get_image().get_pixel(8,8).r>.9,"Tool switching finishes pending repairs")
	studio._set_tool("repair")
	for mode in preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").MODES:
		tool.mode=mode; studio._refresh_context(); preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").options(studio)
		for node in studio.get_children():
			if node is PopupPanel: node.queue_free()
		await process_frame
	tool.mode="procedural"; tool.generate("::new::"); await wait_repair(tool)
	check(studio.document.layers.size()==2 and studio._main_layer().properties.get("texture_recipe") is KiwiImageTextureRecipe,"Procedural layer saves its editable recipe")
	var path:="res://.godot/repair_document_test.tres"
	check(ResourceSaver.save(studio.document,path)==OK,"Repair document saves")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(loaded!=null and loaded.layers.size()==2 and loaded.layers[-1].properties.texture_recipe is KiwiImageTextureRecipe,"Recipes and repaired pixels reopen in a native document")
	var preset:=KiwiImagePatternPreset.new(); preset.texture=tool.source_image if tool.source_image is Texture2D else ImageTexture.create_from_image(tool.source_image); preset.settings=tool.config.duplicate(true)
	check(ResourceSaver.save(preset,"res://.godot/repair_pattern_test.tres")==OK,"Pattern presets save as native resources")
	var restored:=ResourceLoader.load("res://.godot/repair_pattern_test.tres","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImagePatternPreset
	check(restored!=null and restored.texture.get_image().get_data()==preset.texture.get_image().get_data(),"Pattern preset save/reopen preserves its source pixels")
	studio._refresh_context()
	for i in 5: await process_frame
	root.get_texture().get_image().save_png("res://.godot/texture_repair_ui.png")
	root.gui_embed_subwindows=true; mode_picker=studio.find_child("RepairMode",true,false) as MenuButton
	mode_picker.get_popup().position=Vector2i(mode_picker.global_position+Vector2(0,mode_picker.size.y)); mode_picker.get_popup().popup()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("res://.godot/repair_mode_menu_ui.png")
	studio.queue_free()
	for i in 6: await process_frame
