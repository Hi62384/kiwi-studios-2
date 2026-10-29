extends "res://scripts/actors/tests/surface_growth_test.gd"
const Link=preload("res://Workspaces/ModelWorkspace/model_source_link.gd")
func run() -> void:
	var model:=KiwiModelSession.new(); var item:=model.add("Box"); item.transform.origin=Vector3(1,2,3); item.structural={&"structure_connections":{"support":KiwiStructure.connection(item.id,Vector3.ZERO,Vector3(1,0,0))},&"structure_enabled":true}; var file:="user://source_defaults.res"; ResourceSaver.save(model.document,file); var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var source_scene:=model.document.actor_scene(registry,file); var one:=source_scene.actors[0]; one.values[&"model_component_instance_id"]="one"; one.id="first_instance"; one.values[&"structure_connections"].support.target=one.id; var two:=one.copy_actor(); two.id="second_instance"; two.values[&"model_component_instance_id"]="two"; two.values[&"structure_connections"].support.target=two.id; Link.register_actor(one); Link.register_actor(two)
	one.values[&"position"]=Vector3(99,2,3); one.values[&"structure_connections"].support.strength=.3; var original:=Link.load_resource(file)
	check(original==Link.load_resource(ProjectSettings.globalize_path(file)),"Equivalent model paths share one immutable native source snapshot")
	item.transform.origin=Vector3(4,5,6); item.structural[&"structure_connections"].support.target_pivot=Vector3(2,0,0); item.structural[&"structure_connections"].support.strength=.7; ResourceSaver.save(model.document,file); Link.invalidate(file); Link.refresh(one,file); Link.refresh(two,file)
	check(one.values[&"position"]==Vector3(99,2,3) and two.values[&"position"]==Vector3(4,5,6),"Source pose updates preserve a scene position override while updating the default instance")
	check(is_equal_approx(one.values[&"structure_connections"].support.strength,.3) and is_equal_approx(two.values[&"structure_connections"].support.strength,.7),"Structural defaults update without overwriting a custom scene joint value")
	check(one.values[&"structure_connections"].support.target==one.id and two.values[&"structure_connections"].support.target==two.id,"Independent model instances keep their own remapped structural targets")
	check(one.values[&"structure_connections"].support.target_pivot==Vector3(2,0,0),"Unmodified nested joint pivots update even when another joint field is overridden")
	check(Link.load_resource(file)!=original,"Saved-source invalidation replaces the cached source snapshot")
	print("MODEL SOURCE DEFAULTS: %d checks, %d failures"%[checks,failures]); quit(failures)
