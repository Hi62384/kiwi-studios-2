extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Connections=preload("res://Workspaces/EnvironmentWorkspace/world/world_connections.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func connected(graph: Dictionary,a: String,b: String) -> bool:
	a=str(graph.get("node_aliases",{}).get(a,a)); b=str(graph.get("node_aliases",{}).get(b,b)); var visited: Dictionary={a:true}; var queue: Array[String]=[a]; var at:=0
	while at<queue.size():
		var current:=queue[at]; at+=1
		if current==b: return true
		for edge: Dictionary in graph.edges:
			var next: String=edge.to if edge.from==current else (edge.from if edge.to==current else "")
			if not next.is_empty() and not visited.has(next): visited[next]=true; queue.append(next)
	return false
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Cities.create(Worlds.source(world),Vector3(-70,0,0)); source=Cities.create(source,Vector3(70,0,0))
	for settlement: Dictionary in source.settlements: settlement.radius=16.; settlement.blocks=1; settlement.height_max=1
	var result:=await Edit.request(session,id,source); var owner:=session.document.component(id); var records: Array=owner.parameters.get("world_connections",[])
	check(result.errors.is_empty() and records.size()==1 and records[0].bridges==0,"Two dry settlements generate one native connecting road rather than disconnected local street grids")
	if records.is_empty(): print(result); quit(1); return
	var record: Dictionary=records[0]; check(connected(owner.parameters.world_graph,record.roads[0].from,record.roads[-1].to),"The connection shares explicit topology with both settlement street networks")
	var next: Resource=Connections.make_editable(Worlds.source(owner),record); result=await Edit.request(session,id,next); owner=session.document.component(id); check(result.errors.is_empty() and Worlds.source(owner).roads.size()>0 and owner.parameters.world_connections.is_empty(),"Generated connections promote to editable sources without duplicate automatic roads")
	session.undo(); owner=session.document.component(id); check(Worlds.source(owner).roads.is_empty() and owner.parameters.world_connections.size()==1,"Making connection roads editable is one undoable transaction")
	var terrain:=session.environment().terrain(Worlds.source(owner).terrain_id); terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.manual_rivers=[{"id":"river","points":PackedVector3Array([Vector3(0,0,-128),Vector3(0,0,128)]),"width":12.,"depth":1.,"follow_terrain":false}]; terrain.prepare_water(); next=Worlds.source(owner).copy(); result=await Edit.request(session,id,next,"Bridge settlements over river"); owner=session.document.component(id); records=owner.parameters.get("world_connections",[])
	check(result.errors.is_empty() and records.size()==1 and int(records[0].bridges)>0,"A real terrain river creates an elevated bridge with graded approach ramps")
	print("BRIDGE DIAGNOSTICS errors=",result.errors," warnings=",result.warnings," connections=",records.size()," occupied=",Worlds.source(owner).occupied.size())
	var piers:=false; var clear:=true; var field: RefCounted=Worlds.source(owner).terrain_field
	if not records.is_empty():
		for road: Dictionary in records[0].roads:
			for point: Vector3 in road.points:
				var sample: Dictionary=field.sample(Vector2(point.x,point.z))
				if sample.get("water",false): clear=clear and point.y>float(sample.water_level)+.6
	for item in session.document.components:
		if item.title=="Supports" and item.mesh!=null: piers=true; clear=clear and item.mesh.bounds().position.y<0.
	check(piers and clear,"Automatic bridge decks clear actual water levels and supports reach the sampled riverbed")
	var snapshot: Dictionary=field.sample(Vector2(0,0)); var original: float=snapshot.water_level; terrain.hydrology.manual_rivers[0].points=PackedVector3Array([Vector3(0,-.1,-128),Vector3(0,-.1,128)]); terrain.prepare_water(); check(not field.valid(session) and absf(float(field.sample(Vector2(0,0)).water_level)-original)<.001,"Water changes invalidate the dependency without mutating a worker's snapshot")
	next=Worlds.source(owner).copy(); next.connection_bridges=false; result=await Edit.request(session,id,next); owner=session.document.component(id); check(result.errors.is_empty() and owner.parameters.world_connections.is_empty() and not result.warnings.is_empty(),"Disabling bridges reports the disconnected water barrier instead of making an underwater road")
	print("WORLD CONNECTIONS: %d checks, %d failures"%[checks,failures]); quit(failures)


