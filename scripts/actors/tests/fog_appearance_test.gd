extends "res://scripts/actors/tests/surface_growth_test.gd"
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
func run() -> void:
	var registry:=ActorRegistry.new(); check(BasicActors.register_all(registry),"Fog objects and global actor register without invalid defaults")
	check(registry.get_definition(&"global_fog")!=null and registry.get_object_definition(&"fog_appearance")!=null and registry.get_object_definition(&"fog_field")!=null,"Global fog, appearance and fields use the common actor/object registry")
	var v:=Appearance.definition().create_object().values
	check(Appearance.optical_density(0.,v)==0.,"Contrast preserves empty spatial regions")
	v[&"opacity"]=.5; var density:=Appearance.optical_density(1.,v)
	check(is_equal_approx(density,.5) and exp(-density*4.)<exp(-density),"Opacity scales extinction and longer optical paths attenuate more")
	v[&"opacity"]=0.; check(Appearance.optical_density(1.,v)==0.,"Zero opacity removes extinction")
	check(Field.combine(1.,.5,4,1.)==.5 and Field.combine(1.,0.,1,1.)==0.,"Density subtraction and multiplication have explicit nonnegative rules")
	check(Field.combine(1.,0.,3,0.)==1.,"A zero-strength minimum mask leaves unrelated density unchanged")
	var field:=Field.definition().create_object(); field.values[&"mode"]=4; field.values[&"resolution"]=0
	var noise:=Field.noise_for(field.values); var a:=noise.get_noise_3d(.2,.4,.7); field.values[&"seed"]=91; var b:=Field.noise_for(field.values).get_noise_3d(.2,.4,.7); field.values[&"seed"]=1
	check(a!=b and a==Field.noise_for(field.values).get_noise_3d(.2,.4,.7),"Actual 3D noise changes by seed and reproduces exactly")
	var tex:=Field.texture(field.values); var builds:=Field.builds; check(tex==Field.texture(field.values) and builds==Field.builds,"Unchanged procedural fields reuse a bounded 3D texture cache")
	var appearance:=Appearance.preset(4); appearance.values[&"layer_1"]=ActorObjectReference.from_object(field)
	var path:="user://fog-appearance-test.tres"; check(ResourceSaver.save(appearance,path)==OK,"Reusable appearance saves with nested field dependencies")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(loaded.type_id==&"fog_appearance" and loaded.get_value(&"secondary")==appearance.get_value(&"secondary") and ActorAnimation.resolve_reference(loaded.get_value(&"layer_1")).get_value(&"seed")==1,"Appearance colors and nested field settings reopen intact"); DirAccess.remove_absolute(path)
	var model:=ActorTimeline.new(); var definition:=registry.get_definition(&"fog_volume"); var clip:=model.create_actor(definition,0.); var actor:=model.actor_for_id(clip.actor_id)
	model.edit_property(actor,definition,&"appearance",ActorObjectReference.from_object(appearance)); model.history.undo(); check(actor.get_value(&"appearance")==null,"Appearance assignment is undoable"); model.history.redo()
	check(ActorAnimation.resolve_reference(actor.get_value(&"appearance"))!=null,"Appearance assignment redoes")
	var path_color:=PackedStringArray(["appearance","color"]); model.playhead_time=0.; model.add_keyframe(actor,path_color,"Fog color",Color.RED); model.playhead_time=1.; model.add_keyframe(actor,path_color,"Fog color",Color.BLUE)
	var sampled:=ActorAnimation.sampled_values(actor,.5); var middle:=ActorAnimation.resolve_reference(sampled[&"appearance"])
	check(middle.get_value(&"color").is_equal_approx(Color(.5,0,.5)),"Nested fog appearance colors interpolate on the existing actor timeline")
	var restored:=ActorAnimation.sampled_values(actor,0.); check(ActorAnimation.resolve_reference(restored[&"appearance"]).get_value(&"color")==Color.RED,"Backward seeking reconstructs the same appearance deterministically")
	model.history.clear_history(); print("FOG APPEARANCE: %d checks, %d failures"%[checks,failures]); quit(failures)
