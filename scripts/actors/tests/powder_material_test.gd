extends SceneTree
var failures:=0
var checks:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var view:=SubViewport.new(); view.size=Vector2i(800,600); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var definition:=editor.registry.get_definition(&"powder"); editor.model.create_actor(definition,0,{&"powder_dimensions":Vector3(.5,.5,.5)})
	var actor:=editor.model.selected_actor(); var geometries:={}; var densities:={}
	for i in 7:
		var preset:=KiwiPowderMaterial.preset(i); var meshes:=KiwiPowderGeometry.variants(preset.values)
		geometries[hash(meshes[0].surface_get_arrays(0))]=true; densities[preset.values.powder_density]=true
		check(meshes.size()==3 and meshes[0].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size()>0,KiwiPowderMaterial.NAMES[i]+" has cached textured grain geometry")
	check(geometries.size()==7 and densities.size()>=6,"All seven presets differ geometrically and use distinct physical recipes")
	KiwiPowderMaterial.apply(editor.model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(3)))
	var physical: float=actor.values.powder_density; var old_material: ActorObjectReference=actor.values.powder_material
	KiwiPowderMaterial.apply(editor.model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(1)),1)
	check(actor.values.powder_density==physical and KiwiPowderMaterial.appearance(actor.values).powder_grain_shape==3,"Appearance-only leaves adopted physical properties intact")
	editor.model.undo(); check(actor.values.powder_material==old_material,"Preset application is one undoable action")
	editor.model.redo(); var snow: ActorObjectReference=actor.values.powder_material
	KiwiPowderMaterial.apply(editor.model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(4)),2)
	check(actor.values.powder_material==snow and actor.values.powder_density==300.,"Physics-only preserves the visual material reference")
	await seek(.2); var generation:=editor.physics.generation
	var material:=ActorAnimation.resolve_reference(actor.values.powder_material); var object_definition:=editor.registry.get_object_definition(&"powder_material")
	editor.model.edit_object_property(actor,material,object_definition,&"powder_color",Color.RED); await seek(.2)
	check(editor.physics.generation==generation,"Editing linked material appearance preserves trajectory caches")
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id) as KiwiPowderRuntime
	check(runtime.grain_material.get_shader_parameter("base_color")==Color.RED,"Linked material color updates the actual instanced grain shader")
	var identity:=runtime.identities.duplicate(true); await seek(.3)
	check(runtime.identities==identity,"Moving grains retain stable geometry, orientation and random surface identity")
	var texture:=Image.create(8,8,false,Image.FORMAT_RGBA8); texture.fill(Color.GREEN)
	var image:=editor.registry.get_object_definition(&"image").create_object(); image.values[&"source"]=ImageTexture.create_from_image(texture)
	material.values[&"powder_texture"]=ActorObjectReference.from_object(image)
	material.values[&"powder_texture_scale"]=Vector2(2,3); material.emit_changed(); await seek(.3)
	check(runtime.grain_material.get_shader_parameter("has_albedo") and runtime.grain_material.get_shader_parameter("texture_scale")==Vector2(2,3),"Texture dependencies and local UV transforms reach the moving grain material")
	var path:="user://powder_material_"+ActorData.new_id()+".tres"
	check(ResourceSaver.save(material,path)==OK,"Powder Material saves through standard resource serialization")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(loaded.type_id==&"powder_material" and loaded.values.powder_texture.embedded.values.source.get_image().get_pixel(0,0).g>.9 and loaded.values.material_id==material.values.material_id,"Material identity, settings and embedded image dependencies survive reopening")
	var shared:=ActorObjectReference.from_asset(path,&"powder_material")
	editor.model.create_actor(definition,1); var second:=editor.model.selected_actor(); KiwiPowderMaterial.apply(editor.model,[actor,second],shared,1)
	var common:=ActorAnimation.resolve_reference(actor.values.powder_material)
	common.set_value(&"powder_roughness",.17)
	check(is_equal_approx(KiwiPowderMaterial.appearance(second.values).powder_roughness,.17),"Saved material references share appearance edits")
	KiwiPowderMaterial.apply(editor.model,[second],second.values.powder_material.make_unique(func(file: String): return ResourceLoader.load(file)),1)
	common.set_value(&"powder_roughness",.7)
	check(is_equal_approx(KiwiPowderMaterial.appearance(second.values).powder_roughness,.17),"Make Unique breaks material sharing without altering the original")
	var store:=KiwiClipboardStore.new("user://powder_material_clipboard_"+ActorData.new_id()); var id:=store.save(loaded,"Reusable powder")
	var portable:=ResourceLoader.load(store.entry_path(id),"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(portable!=null and portable.values.powder_texture.embedded.values.source.get_image().get_pixel(0,0).g>.9,"Super Clipboard preserves powder materials and portable image dependencies")
	var track:=ActorAnimationTrack.new(); track.path=PackedStringArray(["powder_material","powder_color"])
	for pair in [[0.,Color.RED],[1.,Color.BLUE]]:
		var key:=ActorKeyframe.new(); key.time=pair[0]; key.value=pair[1]; track.keys.append(key)
	actor.animation_tracks.append(track); await seek(0); generation=editor.physics.generation; await seek(.5)
	check(runtime.grain_material.get_shader_parameter("base_color").b>.4 and editor.physics.generation==generation,"Nested material appearance keyframes animate without restarting simulation")
	editor.model.edit_property(actor,definition,&"powder_density",900.); await seek(.5)
	check(editor.physics.generation>generation,"Changing the actor's adopted physical density invalidates trajectories")
	var before:=KiwiPowderGeometry.builds; await seek(.5); await seek(.5)
	check(KiwiPowderGeometry.builds==before,"Repeated previews reuse geometry variants rather than regenerating meshes")
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("POWDER MATERIALS: %d checks, %d failures"%[checks,failures]); quit(failures)
