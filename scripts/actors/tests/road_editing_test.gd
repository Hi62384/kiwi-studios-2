extends "res://scripts/actors/tests/surface_growth_test.gd"
const Editing=preload("res://Workspaces/EnvironmentWorkspace/world/road_editing.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var id:=world.id; var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-20,0,0),Vector3(20,0,0)); var original: Dictionary=source.roads[0].duplicate(true); var reversed:=Editing.reverse(source,0)
	check(reversed.error.is_empty() and reversed.source.roads[0].from==original.to and reversed.source.roads[0].points[0]==original.points[-1] and source.roads[0]==original,"Reversing a road swaps its endpoints and control points without modifying the original source")
	var split:=Editing.split(source,0); var next: Resource=split.source; check(next.validate().is_empty() and next.roads.size()==2 and next.roads[0].to==next.roads[1].from and next.nodes[next.roads[0].to]==Vector3.ZERO,"Splitting a road creates two valid sources sharing an explicit graph node")
	var result:=await Edit.request(session,id,next); check(result.errors.is_empty() and session.document.component(id).parameters.world_graph.adjacency[next.roads[0].to].size()==2,"Split sources install as connected native road geometry")
	session.undo(); var undone: bool=Worlds.source(session.document.component(id)).roads.is_empty(); session.redo(); check(undone and Worlds.source(session.document.component(id)).roads.size()==2,"Split installation and all its road details are undoable together")
	var joined:=Editing.join(next,0,1); check(joined.source!=null and joined.source.roads.size()==1 and joined.source.roads[0].points.size()==3 and joined.source.validate().is_empty(),"Joining roads preserves their shared bend and cleans unused source nodes")
	var removed:=Editing.remove_point(joined.source,0,1); check(removed.source.roads[0].points.size()==2 and removed.source.validate().is_empty(),"Deleting an internal control point keeps a valid source road")
	check(Editing.remove_point(removed.source,0,0).source==null,"Control-point deletion cannot reduce a road to an invalid one-point path")
	var extended: Resource=Worlds.add_road(source,Vector3(20,0,0),Vector3(40,0,0)); var graph:=Roads.graph(extended); check(extended.roads[1].from==extended.roads[0].to and graph.adjacency[extended.roads[0].to].size()==2,"Collinear road extensions share endpoint identity instead of merely touching visually")
	var endpoint:=Editing.remove_point(joined.source,0,0); check(endpoint.source!=null and endpoint.source.validate().is_empty() and endpoint.source.nodes[endpoint.source.roads[0].from]==Vector3.ZERO,"Deleting an endpoint updates the source node without moving unrelated connected roads")
	print("ROAD EDITING: %d checks, %d failures"%[checks,failures]); quit(failures)

