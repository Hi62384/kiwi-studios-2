extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Blocks=preload("res://Workspaces/EnvironmentWorkspace/world/world_blocks.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Editing=preload("res://Workspaces/EnvironmentWorkspace/world/road_editing.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func closed_roads(source: Resource,polygon: PackedVector2Array) -> Resource:
	var next: Resource=source
	for index in polygon.size():
		var a:=polygon[index]; var b:=polygon[(index+1)%polygon.size()]; next=Worlds.add_road(next,Vector3(a.x,.03,a.y),Vector3(b.x,.03,b.y))
	return next
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3.ZERO,true); var id:=world.id; var square:=PackedVector2Array([Vector2(-40,-40),Vector2(40,-40),Vector2(40,40),Vector2(-40,40)]); var source: Resource=closed_roads(Worlds.source(world),square); var graph:=Roads.graph(source); var result:=Blocks.extract(graph)
	check(result.blocks.size()==1 and absf(Blocks._area(result.blocks[0].polygon)-6400.)<.1,"Half-edge traversal extracts one actual bounded road face and discards the exterior")
	var block_id: String=result.blocks[0].id; var split:=Editing.split(source,0); result=Blocks.extract(Roads.graph(split.source)); check(result.blocks.size()==1 and result.blocks[0].id==block_id,"Splitting a boundary road preserves its block identity through source-family lineage")
	var divided: Resource=Worlds.add_road(source,Vector3(0,.03,-40),Vector3(0,.03,40)); result=Blocks.extract(Roads.graph(divided)); check(result.blocks.size()==2,"Adding a connected internal street divides the block into two bounded faces")
	var spur: Resource=Worlds.add_road(source,Vector3(0,.03,-40),Vector3(0,.03,-10)); result=Blocks.extract(Roads.graph(spur)); check(result.blocks.size()==1,"A dead-end street does not invalidate the surrounding bounded block")
	source=Cities.create(source,Vector3.ZERO); source.settlements[0].radius=64.; source.settlements[0].layout_mode="Road network"; source.settlements[0].height_max=1; var generated:=await Edit.request(session,id,source); var owner:=session.document.component(id); var plots: Array=owner.parameters.get("world_plots",[]); var buildings:=0; var valid:=true
	for item in session.document.components:
		if item.parameters.has("architecture_source"): buildings+=1
	for plot: Dictionary in plots: valid=valid and Blocks.contains_rectangle(plot.polygon,plot.pose,float(plot.width),float(plot.depth))
	check(generated.errors.is_empty() and buildings>=4 and plots.size()==buildings and valid,"Road-derived frontage lots fit actual native building rectangles inside their clipped parcels")
	check(session.environment().validate().is_empty() and owner.parameters.world_blocks.size()==1,"Road-network settlements preserve native hierarchy, source and mesh validation")
	var concave:=PackedVector2Array([Vector2(-40,-40),Vector2(40,-40),Vector2(40,0),Vector2(0,0),Vector2(0,40),Vector2(-40,40)]); var other:=KiwiEnvironmentSession.new(); var other_world:=Worlds.add(other); var shaped: Resource=closed_roads(Worlds.source(other_world),concave); var faces:=Blocks.extract(Roads.graph(shaped)); var settlement: Dictionary={"id":"concave","setback":2.,"lot_size":18.}; var fitted:=Blocks.plots(faces.blocks[0],settlement,128); valid=not fitted.is_empty()
	for plot: Dictionary in fitted: valid=valid and Blocks.contains_rectangle(concave,plot.pose,float(plot.width),float(plot.depth)) and Blocks.contains_rectangle(plot.polygon,plot.pose,float(plot.width),float(plot.depth))
	check(faces.blocks.size()==1 and valid,"Concave road blocks produce contained frontage buildings instead of bounding-box buildings crossing the cutout")
	var customized: KiwiModelComponent
	for item in session.document.components:
		if item.parameters.has("architecture_source"): customized=item; break
	customized.parameters.architecture_source.roof_pitch+=1.; var next: Resource=Worlds.source(owner).copy(); next.settlements.clear(); generated=await Edit.request(session,id,next); check(not generated.errors.is_empty() and session.document.component(customized.id)!=null,"A topology change cannot silently delete a customized generated building")
	print("WORLD BLOCKS: %d checks, %d failures"%[checks,failures]); quit(failures)
