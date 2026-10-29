extends "res://scripts/actors/tests/surface_growth_test.gd"
const Library=preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Props=preload("res://Workspaces/EnvironmentWorkspace/world/world_props.gd")
func run() -> void:
	var valid:=true; var models: Array=[]
	for kind in Library.NAMES:
		var model:=Library.model(kind); valid=valid and model.validate().is_empty() and model.components.size()>=3; models.append(model)
	check(valid and models.size()==8,"Eight built-in props are editable multi-component native models with real geometry")
	var lamp: KiwiModelDocument=models[1]; var lens:=lamp.components[-1].surface_materials[0] as StandardMaterial3D; check(lens!=null and lens.emission_enabled and lens.emission_energy_multiplier>1.,"Lamp fixtures have an emissive lens material rather than a placeholder color")
	var session:=KiwiEnvironmentSession.new(); var owner:=Worlds.add(session,Vector3(10,2,8),true); var id:=owner.id; var source: Resource=Worlds.add_road(Worlds.source(owner),Vector3(-40,.03,0),Vector3(40,.03,0)); source=Library.add(source,"Park bench"); source.prop_rules[0].spacing=10.; var result:=await Edit.request(session,id,source); owner=session.document.component(id); var layer:=session.document.component(id+":props:"+str(source.prop_rules[0].id)); var rules:=session.environment().component_settings[layer.id].scatter as KiwiEnvironmentScatter; var generated:=rules.generate(session.environment().terrain(rules.terrain_id)); var fitted: bool=generated.count>0; var expected:=3.+.3+.14+.75
	for batch: Array in generated.batches.values():
		for pose: Transform3D in batch: fitted=fitted and absf(absf(pose.origin.z)-expected)<.001 and absf(pose.origin.y-.195)<.001
	check(result.errors.is_empty() and fitted and rules.anchor_height_mode==2,"Sidewalk props occupy actual pavement positions and curb elevation instead of being rejected by road masks or sunk into terrain")
	var graph:=Roads.graph(Worlds.source(owner)); var filter: Dictionary=Worlds.source(owner).prop_rules[0].duplicate(true); filter.road_types=PackedStringArray(["Highway"]); check(Props._anchors(filter,graph,Callable()).poses.is_empty(),"Contextual road-type filters skip incompatible streets")
	var changed: Resource=Worlds.source(owner).copy(); changed.roads[0].type="Dirt Road"; changed.roads[0].sidewalk=0.; graph=Roads.graph(changed); check(Props._anchors(changed.prop_rules[0],graph,Callable()).poses.is_empty(),"Pavement-only fixtures avoid rural roads with no sidewalks")
	var terrain:=session.environment().terrain(rules.terrain_id); var height_rules:=rules.duplicate(true) as KiwiEnvironmentScatter; height_rules.anchor_height_mode=0; var terrain_result:=height_rules.generate(terrain); height_rules.anchor_height_mode=1; var offset_result:=height_rules.generate(terrain)
	check(not terrain_result.batches.is_empty() and (terrain_result.batches[0][0] as Transform3D).origin.y==0. and absf((offset_result.batches[0][0] as Transform3D).origin.y-.195)<.001,"Anchor terrain, offset and authored-height modes evaluate actual generated transforms")
	height_rules.minimum_distance=100.; var limited:=height_rules.generate(terrain); check(limited.count<limited.requested and str(limited.error).is_empty() and not str(limited.get("warning","")).is_empty(),"Legitimate spacing and exclusion limits report a placement warning rather than invalid renderer output")
	var saved:=ResourceSaver.save(session.environment(),"user://world_prop_library_test.res"); var loaded:=ResourceLoader.load("user://world_prop_library_test.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).prop_rules[0].model.components.size()>=3 and (loaded.component_settings[layer.id].scatter as KiwiEnvironmentScatter).anchor_height_mode==2,"World props save self-contained model geometry, materials and sidewalk-height settings")
	session.undo(); check(Worlds.source(session.document.component(id)).prop_rules.is_empty(),"Creating the built-in world prop layer undoes as a native world action")
	session.redo(); check(session.document.component(layer.id)!=null,"Redo restores the built-in model palette and generated layer")
	print("WORLD PROP LIBRARY: %d checks, %d failures"%[checks,failures]); quit(failures)

