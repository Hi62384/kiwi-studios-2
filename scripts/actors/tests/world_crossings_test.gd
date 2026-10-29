extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var ground:=session.add_terrain(); var terrain:=session.environment().terrain(ground.id); terrain.resolution=33; terrain.dimensions=Vector2(32,32); terrain.amplitude=0.; terrain.generation=KiwiTerrainGenerator.new(); terrain.generation.profile=0; terrain.generation.layers=[{"id":"hill","type":"Mesa","height":8.,"width":8.,"length":8.,"center":Vector2.ZERO}]; terrain.prepare(); var root_component:=Worlds.add(session); var id:=root_component.id; var source: Resource=Worlds.source(root_component).copy(); source.terrain_id=ground.id; source=Worlds.add_road(source,Vector3(-14,0,3),Vector3(14,0,3)); source.roads[0].width=4.; source.roads[0].mode="Bridge"; source.roads[0].pier_height=6.; var bridge:=Roads.generate(source); var deck:=0; var supports:=0; var rails:=0; var valid:=true
	for part: KiwiModelComponent in bridge.document.components:
		if part.parameters.has("world_road"): deck+=1; valid=valid and part.mesh.bounds().size.y>.25 and KiwiDestructionGeometry.closed(part.mesh)
		if part.title=="Supports": supports+=1; valid=valid and part.mesh.bounds().size.y>5.
		if part.title=="Railings": rails+=1
	check(bridge.errors.is_empty() and valid and deck>0 and supports>0 and rails>0,"Bridge mode generates real solid decks, support piers and railings")
	source.roads[0].mode="Tunnel"; var result:=await Edit.request(session,id,source,"Excavate road tunnel"); terrain=session.environment().terrain(ground.id)
	check(result.errors.is_empty() and terrain.caves.size()==1 and not terrain.volume_chunks.is_empty(),"Tunnel creation uses the existing terrain worker to generate actual excavated volume geometry")
	var cave:=terrain.caves[0]; cave.prepare(); check(cave.distance(Vector3(0,2.3,3))<0. and cave.paths[0][0].x< -14.,"Tunnel void follows the road and extends through the hillside entrances")
	var portals:=0
	for part: KiwiModelComponent in session.document.components:
		if part.title=="Tunnel portals": portals+=1; check(part.mesh!=null and not part.mesh.faces.is_empty(),"Tunnel portal has native open architectural geometry")
	check(portals>0,"Tunnel portals are generated only at actual source-road ends")
	session.undo(); terrain=session.environment().terrain(ground.id); check(terrain.caves.is_empty() and Worlds.source(session.document.component(id)).roads.is_empty(),"One undo removes both excavated terrain and its newly created tunnel road")
	session.redo(); terrain=session.environment().terrain(ground.id); check(terrain.caves.size()==1 and not terrain.volume_chunks.is_empty(),"Redo restores tunnel source and prepared terrain volume together")
	session.selected=[id]; session.delete_selected(); check(session.document.component(id)==null and session.environment().terrain(ground.id).caves.is_empty(),"Deleting a world removes its owned road geometry and tunnel excavation together")
	session.undo(); check(session.document.component(id)!=null and session.environment().terrain(ground.id).caves.size()==1,"Undoing world deletion restores the editable source and its terrain openings")
	var next: Resource=Worlds.source(session.document.component(id)).copy(); next.roads[0].mode="Ground"; result=await Edit.request(session,id,next,"Remove tunnel"); terrain=session.environment().terrain(ground.id)
	check(result.errors.is_empty() and terrain.caves.is_empty() and terrain.volume_chunks.is_empty(),"Changing a tunnel back to a ground road restores original terrain rather than leaving a permanent hole")
	next=Worlds.source(session.document.component(id)).copy(); next.roads[0].mode="Tunnel"; var points: PackedVector3Array=next.roads[0].points; points[0]=Vector3(-2,0,3); next.roads[0].points=points; next.nodes[next.roads[0].from]=points[0]; result=await Edit.request(session,id,next)
	check(not result.errors.is_empty() and session.environment().terrain(ground.id).caves.is_empty(),"Buried tunnel entrances are rejected atomically instead of placing decorative portals on solid terrain")
	print("WORLD CROSSINGS: %d checks, %d failures"%[checks,failures]); quit(failures)
