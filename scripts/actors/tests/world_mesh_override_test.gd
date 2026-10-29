extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var id:=world.id; var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-25,0,5),Vector3(25,0,5)); var result:=await Edit.request(session,id,source); var road: KiwiModelComponent
	for component in session.document.components:
		if component.parameters.has("world_road"): road=component; break
	check(result.errors.is_empty() and road!=null and int(road.parameters.get("world_mesh_version",0))==2,"Installed world geometry records UV and material-slot baselines")
	var road_id:=road.id; session.action("Edit road UV",func(): var uv: PackedVector2Array=road.mesh.uv[0]; uv[0]+=Vector2(.25,.5); road.mesh.uv[0]=uv); var authored:=road.mesh.copy_mesh(); source=Worlds.source(session.document.component(id)).copy(); source.roads[0].width+=2.; result=await Edit.request(session,id,source)
	check(result.errors.is_empty() and session.document.component(road_id).mesh.uv==authored.uv and session.document.component(road_id).mesh.vertices==authored.vertices,"Regeneration preserves a manually edited UV mesh even when its procedural source changes")
	source=Worlds.source(session.document.component(id)).copy(); source.render_distance+=100.; result=await Edit.request(session,id,source); check(result.errors.is_empty() and session.document.component(road_id).mesh.uv==authored.uv,"Manual UV overrides remain recognized on subsequent regenerations")
	session.undo(); session.redo(); check(session.document.component(road_id).mesh.uv==authored.uv,"Undo/redo preserves explicit native mesh overrides")
	print("WORLD MESH OVERRIDES: %d checks, %d failures"%[checks,failures]); quit(failures)
