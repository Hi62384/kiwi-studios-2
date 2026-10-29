extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Dependencies=preload("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd")
func refreshed(workspace: Control,id: String) -> bool:
	Dependencies.state(workspace).time=-1000
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var source:=Worlds.source(workspace.session.document.component(id))
		if source!=null and source.terrain_field!=null and source.terrain_field.valid(workspace.session) and not Edit.pending.has(workspace.session.get_instance_id()) and workspace._generation_jobs.is_empty(): return true
	return false
func wait_history(workspace: Control) -> void:
	var deadline:=Time.get_ticks_msec()+450
	while Time.get_ticks_msec()<deadline: await process_frame
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Cities.create(Worlds.source(world),Vector3.ZERO); source.settlements[0].radius=16.; source.settlements[0].blocks=1; source.settlements[0].height_max=1; source=Worlds.add_road(source,Vector3(-25,.03,-40),Vector3(25,.03,-40)); var result:=await Edit.request(workspace.session,id,source); var terrain_id:=str(Worlds.source(workspace.session.document.component(id)).terrain_id); var building_id:=""
	for item in workspace.session.document.components:
		if item.parameters.has("architecture_source"): building_id=item.id; break
	check(result.errors.is_empty() and not building_id.is_empty(),"Live dependency test starts with native ground, a town and a terrain-following road")
	var original: float=workspace.session.document.component(building_id).transform.origin.y; var depth:=workspace.session._undo.size(); var terrain:=workspace.session.environment().terrain(terrain_id)
	workspace.session.action("Raise ground",func(): terrain.base_height=1.; terrain.prepare(); workspace.session.document.component(terrain_id).mesh=terrain.editable_mesh())
	var ready:=await refreshed(workspace,id); var shifted: float=workspace.session.document.component(building_id).transform.origin.y
	check(ready and absf(shifted-original-1.)<.01,"Changing terrain automatically refreshes native building elevations without a manual world refresh")
	check(workspace.session._undo.size()==depth+1,"The dependent world update merges into the original terrain action")
	var followed: Resource=Worlds.source(workspace.session.document.component(id)); check(absf(float(followed.roads[0].points[0].y)-1.03)<.01,"Authored road control points follow changed terrain in the same update")
	workspace.session.undo(); await wait_history(workspace); check(absf(workspace.session.environment().terrain(terrain_id).base_height)<.01 and absf(workspace.session.document.component(building_id).transform.origin.y-original)<.01 and workspace.session._undo.size()==depth,"One undo restores terrain and dependent geometry without an automatic reapply")
	workspace.session.redo(); await wait_history(workspace); check(absf(workspace.session.environment().terrain(terrain_id).base_height-1.)<.01 and absf(workspace.session.document.component(building_id).transform.origin.y-shifted)<.01,"Redo restores the combined terrain and world state")
	depth=workspace.session._undo.size(); var center_before:=workspace.session.environment().terrain(terrain_id).height(64,64); workspace.session.begin_terrain(terrain_id); workspace.session.sculpt(Vector2.ZERO,50.,.3,.4,0); workspace.session.finish_terrain(); ready=await refreshed(workspace,id); var sculpted: float=workspace.session.document.component(building_id).transform.origin.y
	check(ready and sculpted>shifted+.1 and workspace.session._undo.size()==depth+1 and workspace.session._undo.back().get("custom",false),"Sparse sculpt strokes retain their custom history while refreshing dependent world geometry")
	workspace.session.undo(); await wait_history(workspace); check(absf(workspace.session.environment().terrain(terrain_id).height(64,64)-center_before)<.001 and absf(workspace.session.document.component(building_id).transform.origin.y-shifted)<.01,"Undoing a sparse sculpt restores its samples and the preceding world geometry")
	workspace.session.redo(); await wait_history(workspace); check(absf(workspace.session.document.component(building_id).transform.origin.y-sculpted)<.01,"Redoing the sculpt restores its dependent building state")
	depth=workspace.session._undo.size(); var house:=Buildings.add(workspace.session,Vector3(70,1,50)); var deadline:=Time.get_ticks_msec()+15000; Dependencies.state(workspace).time=-1000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not Worlds.source(workspace.session.document.component(id)).occupied.is_empty() and not Edit.pending.has(workspace.session.get_instance_id()): break
	check(Worlds.source(workspace.session.document.component(id)).occupied.any(func(area: Dictionary): return area.owner==house.id) and workspace.session._undo.size()==depth+1,"Adding an independent building automatically reserves its footprint in the same undo action")
	workspace.session.undo(); await wait_history(workspace); check(workspace.session.document.component(house.id)==null and Worlds.source(workspace.session.document.component(id)).occupied.is_empty(),"Undoing independent-object creation restores its placement masks too")
	await Edit.flush(workspace.session); workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD LIVE DEPENDENCIES: %d checks, %d failures"%[checks,failures]); quit(failures)
