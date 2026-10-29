extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3(10,2,7),true); var id:=world.id; var source: Resource=Forests.create(Worlds.source(world),Vector3.ZERO); source=Worlds.add_road(source,Vector3(-80,.03,0),Vector3(80,.03,0)); source.exclusions.append({"polygon":PackedVector2Array([Vector2(10,10),Vector2(30,10),Vector2(30,30),Vector2(10,30)]),"exclude_vegetation":true})
	for forest: Dictionary in source.forests: forest.budget=120
	var result:=await Edit.request(session,id,source,"Generate test forest"); var layers: Array[String]=[]; var rules_list: Array[KiwiEnvironmentScatter]=[]
	for component in session.document.components:
		var rules:=session.environment().component_settings.get(component.id,{}).get("scatter") as KiwiEnvironmentScatter
		if rules==null: continue
		layers.append(component.id); rules_list.append(rules)
	check(result.errors.is_empty() and layers.size()==4 and session.environment().validate().is_empty(),"Forest generation creates four native vegetation layers in the existing environment hierarchy")
	var diverse:=true; var clear:=true; var counts:=0; var repeatable:=true; var density_varying:=true
	for rules in rules_list:
		var placed:=rules.generate(session.environment().terrain(rules.terrain_id)); var again:=rules.generate(session.environment().terrain(rules.terrain_id)); counts+=int(placed.count); repeatable=repeatable and placed.placements==again.placements; diverse=diverse and rules.palette[0].source is KiwiModelDocument and not rules.palette[0].source.components[0].mesh.validate().size()
		for placement: Dictionary in placed.placements.values():
			var point: Vector3=placement.transform.origin; clear=clear and (absf(point.x)>80. or absf(point.z)>3.5+rules.exclusion_margin-.01) and not Rect2(10,10,20,20).has_point(Vector2(point.x,point.z))
		var plain:=rules.duplicate(true) as KiwiEnvironmentScatter; plain.patch_strength=0.; density_varying=density_varying and plain.generate(session.environment().terrain(rules.terrain_id)).placements!=placed.placements
	check(diverse and rules_list[0].palette.size()==2 and rules_list[2].palette.size()==2 and counts>200,"Canopy, smaller trees, understory and ground layers use real editable multi-species natural models")
	check(clear,"Road corridors and protected development polygons exclude trees with layer-specific clearance")
	check(repeatable and density_varying,"Seeded placements are deterministic and smooth clearing fields change their distribution")
	var first_id:=layers[0]; var first:=session.environment().component_settings[first_id].scatter as KiwiEnvironmentScatter; var placed:=first.generate(session.environment().terrain(first.terrain_id)); var candidate: String=placed.placements.keys()[0]; session.action("Paint manual clearing",func(): first.erase_regions.append(Vector3(-25,-25,8)); first.overrides[candidate]={"deleted":true}; first.scale_range=Vector2(.9,1.1))
	var next: Resource=Worlds.source(session.document.component(id)).copy(); next.roads[0].width=12.; result=await Edit.request(session,id,next,"Widen road through forest"); first=session.environment().component_settings[first_id].scatter as KiwiEnvironmentScatter
	check(result.errors.is_empty() and first.erase_regions.size()==1 and first.overrides.get(candidate,{}).get("deleted",false) and first.scale_range==Vector2(.9,1.1),"Regenerating a road preserves forest layer IDs, hand-painted clearings and edited instance rules")
	var widened:=first.generate(session.environment().terrain(first.terrain_id)); clear=true
	for placement: Dictionary in widened.placements.values():
		var point: Vector3=placement.transform.origin; clear=clear and (absf(point.x)>80. or absf(point.z)>6.5+first.exclusion_margin-.01)
	check(clear,"Updating development masks clears vegetation around the widened road")
	session.undo(); var restored:=session.environment().component_settings[first_id].scatter as KiwiEnvironmentScatter; check(restored.exclude_polygons!=first.exclude_polygons and restored.erase_regions.size()==1,"Road and forest-mask regeneration undo together without losing preceding manual edits"); session.redo()
	var path:="user://world_forest.res"; var saved:=ResourceSaver.save(session.environment(),path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and reopened!=null and reopened.validate().is_empty() and reopened.component_settings[first_id].scatter.palette[0].source is KiwiModelDocument,"A world saves and reopens its self-contained natural palettes, layered rules and manual edits")
	var output:=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").generate(Worlds.source(session.document.component(id)),func(): return true); check(output.get("cancelled",false),"Forest world generation honors cancellation without installing partial output")
	var invalid: Resource=Worlds.source(session.document.component(id)).copy(); invalid.forests[0].density=INF; check(not invalid.validate().is_empty(),"Malformed saved forest settings are rejected before scheduling generation")
	print("WORLD FORESTS: %d checks, %d failures"%[checks,failures]); quit(failures)

