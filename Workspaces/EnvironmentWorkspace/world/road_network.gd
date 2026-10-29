extends RefCounted
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd")
static func graph(source: Resource,cancel: Callable=Callable(),settlement_layout: Dictionary={}) -> Dictionary:
	var nodes: Dictionary=source.nodes.duplicate(); nodes.merge(settlement_layout.get("nodes",{}),true); var edges: Array[Dictionary]=[]; var warnings:=PackedStringArray(); var paths: Array=[]; var splits: Array=[]; var authored_roads: Array=source.roads.duplicate(); authored_roads.append_array(settlement_layout.get("roads",[]))
	var canonical:=_canonical(nodes); nodes=canonical.nodes; var aliases: Dictionary=canonical.aliases
	for authored: Dictionary in authored_roads:
		var road:=authored.duplicate(true); road.from=aliases.get(road.from,road.from); road.to=aliases.get(road.to,road.to)
		if not road.get("enabled",true): continue
		var points: PackedVector3Array=Geometry.sample(road.points); points[0]=nodes[road.from]; points[-1]=nodes[road.to]; paths.append({"source":road,"points":points}); var markers: Array=[]
		if str(road.get("mode","Ground"))=="Ground" and road.get("follow_terrain",false) and source.terrain_field!=null:
			var warned:=false
			for index in range(1,points.size()-1):
				var surface: Dictionary=source.terrain_field.sample(Vector2(points[index].x,points[index].z))
				if surface.is_empty(): continue
				points[index].y=float(surface.height)+.03
				if surface.get("water",false) and not warned: warnings.append(str(road.get("name","Road"))+" crosses water. Use bridge mode or route around it."); warned=true
			paths[-1].points=points
		markers.append({"segment":0,"t":0.,"node":road.from}); markers.append({"segment":points.size()-2,"t":1.,"node":road.to}); splits.append(markers)
		# Region borders split ownership, while the same graph node connects both
		# sides. Loading order can never create a second copy of a border road.
		for region: Dictionary in source.regions:
			var bounds: Rect2=region.bounds; var corners:=PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
			for segment in points.size()-1:
				var a:=Vector2(points[segment].x,points[segment].z); var b:=Vector2(points[segment+1].x,points[segment+1].z)
				for border in 4:
					var cross: Variant=Geometry2D.segment_intersects_segment(a,b,corners[border],corners[(border+1)%4])
					if not cross is Vector2: continue
					var t:=a.distance_to(cross)/maxf(.0001,a.distance_to(b)); var position: Vector3=points[segment].lerp(points[segment+1],t); var node:=_node(nodes,position,"border:")
					markers.append({"segment":segment,"t":t,"node":node})
	var candidates:=_candidates(paths,cancel)
	if candidates.get("cancelled",false): return {"cancelled":true}
	if candidates.has("error"): return {"errors":PackedStringArray([str(candidates.error)])}
	for pair: Vector4i in candidates.pairs:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		var left:=pair.x; var right:=pair.z; var i:=pair.y; var j:=pair.w; var a: PackedVector3Array=paths[left].points; var b: PackedVector3Array=paths[right].points
		var cross: Variant=Geometry2D.segment_intersects_segment(Vector2(a[i].x,a[i].z),Vector2(a[i+1].x,a[i+1].z),Vector2(b[j].x,b[j].z),Vector2(b[j+1].x,b[j+1].z))
		if not cross is Vector2: continue
		var point: Vector2=cross; var t:=Vector2(a[i].x,a[i].z).distance_to(point)/maxf(.0001,Vector2(a[i].x,a[i].z).distance_to(Vector2(a[i+1].x,a[i+1].z))); var u:=Vector2(b[j].x,b[j].z).distance_to(point)/maxf(.0001,Vector2(b[j].x,b[j].z).distance_to(Vector2(b[j+1].x,b[j+1].z))); var ay:=lerpf(a[i].y,a[i+1].y,t); var by:=lerpf(b[j].y,b[j+1].y,u)
		if absf(ay-by)>1.: continue # Explicit grade-separated crossing.
		var position:=Vector3(point.x,(ay+by)*.5,point.y); var id:=_node(nodes,position,"junction:"); splits[left].append({"segment":i,"t":t,"node":id}); splits[right].append({"segment":j,"t":u,"node":id})
	for index in paths.size():
		var markers: Array=splits[index]; markers.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.segment)+float(a.t)<float(b.segment)+float(b.t)); var unique: Array=[]
		for marker: Dictionary in markers:
			if unique.is_empty() or unique[-1].node!=marker.node: unique.append(marker)
		for cut in unique.size()-1:
			var first: Dictionary=unique[cut]; var last: Dictionary=unique[cut+1]
			if first.node==last.node: continue
			var points:=PackedVector3Array([nodes[first.node]]); var path: PackedVector3Array=paths[index].points
			for point in range(int(first.segment)+1,int(last.segment)+1):
				if Vector2(points[-1].x,points[-1].z).distance_to(Vector2(path[point].x,path[point].z))>.001: points.append(path[point])
			var end: Vector3=nodes[last.node]
			if Vector2(points[-1].x,points[-1].z).distance_to(Vector2(end.x,end.z))>.001: points.append(end)
			elif points.size()>1: points[-1]=end
			if points.size()<2: continue
			var edge: Dictionary=paths[index].source.duplicate(true); edge.source_road_id=edge.id; edge.source_from=edge.from; edge.source_to=edge.to; edge.id=str(edge.id)+":"+str(first.node)+":"+str(last.node); edge.from=first.node; edge.to=last.node; edge.points=points; var distance:=0.
			for segment in int(first.segment): distance+=path[segment].distance_to(path[segment+1])
			distance+=path[int(first.segment)].distance_to(nodes[first.node]); edge.distance_start=distance; edges.append(edge)
	var adjacency: Dictionary={}
	for edge in edges:
		for id in [edge.from,edge.to]:
			if not adjacency.has(id): adjacency[id]=[]
			adjacency[id].append(edge.id)
	return {"nodes":nodes,"edges":edges,"adjacency":adjacency,"warnings":warnings,"node_aliases":aliases}
static func _canonical(input: Dictionary) -> Dictionary:
	var result: Dictionary={}; var aliases: Dictionary={}; var cells: Dictionary={}; var keys:=input.keys(); keys.sort_custom(func(a: Variant,b: Variant): return str(a)<str(b))
	for key in keys:
		var point: Vector3=input[key]; var cell:=Vector3i((point/.001).floor()); var found:=""
		for z in range(-1,2):
			for y in range(-1,2):
				for x in range(-1,2):
					for candidate: String in cells.get(cell+Vector3i(x,y,z),[]):
						if (result[candidate] as Vector3).distance_to(point)<.001 and (found.is_empty() or candidate<found): found=candidate
		if found.is_empty():
			found=str(key); result[found]=point
			if not cells.has(cell): cells[cell]=[]
			cells[cell].append(found)
		aliases[key]=found
	return {"nodes":result,"aliases":aliases}
static func _candidates(paths: Array,cancel: Callable) -> Dictionary:
	var buckets: Dictionary={}; var pairs: Dictionary={}; var count:=0
	for path in paths.size():
		var points: PackedVector3Array=paths[path].points; count+=points.size()
		if count>65536: return {"error":"Road sampling exceeds 65,536 points. Generate smaller regions or simplify road paths."}
		for segment in points.size()-1:
			if cancel.is_valid() and cancel.call(): return {"cancelled":true}
			var a:=Vector2(points[segment].x,points[segment].z); var b:=Vector2(points[segment+1].x,points[segment+1].z); var low:=Vector2i((a.min(b)/16.).floor()); var high:=Vector2i((a.max(b)/16.).floor()); var current:=Vector2i(path,segment)
			for z in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var cell:=Vector2i(x,z)
					if not buckets.has(cell): buckets[cell]=[]
					for other: Vector2i in buckets[cell]:
						if other.x==path: continue
						pairs[Vector4i(other.x,other.y,path,segment)]=true
						if pairs.size()>500000: return {"error":"This road region exceeds its intersection budget. Split dense networks into smaller regions."}
					buckets[cell].append(current)
	return {"pairs":pairs.keys()}
static func _node(nodes: Dictionary,position: Vector3,prefix: String) -> String:
	for existing in nodes:
		if (nodes[existing] as Vector3).distance_to(position)<.001: return str(existing)
	var id:=prefix+str(position.snapped(Vector3.ONE*.001)); nodes[id]=position; return id
static func generate(source: Resource,cancel: Callable=Callable(),development: KiwiModelDocument=null) -> Dictionary:
	var errors: PackedStringArray=source.validate(); var document:=KiwiModelDocument.new()
	if not errors.is_empty(): return {"document":null,"errors":errors,"warnings":PackedStringArray()}
	if cancel.is_valid() and cancel.call(): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	if development!=null:
		var root:=development.component(source.world_id); root.parameters.world_source=source
		var forests:=_populate(development,source,{"plots":root.parameters.get("world_plots",[])},root.parameters.world_graph,cancel)
		if forests.get("cancelled",false): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
		var failures: PackedStringArray=forests.errors; failures.append_array(development.validate()); return {"document":development if failures.is_empty() else null,"errors":failures,"warnings":forests.warnings,"settings":forests.settings,"development_reused":true}
	var settlement_layout:=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd").layout(source,cancel)
	if settlement_layout.get("cancelled",false): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	if not settlement_layout.get("errors",PackedStringArray()).is_empty(): return {"document":null,"errors":settlement_layout.errors,"warnings":settlement_layout.warnings}
	var graph_data:=graph(source,cancel,settlement_layout)
	if graph_data.get("cancelled",false): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	if graph_data.has("errors"): return {"document":null,"errors":graph_data.errors,"warnings":PackedStringArray()}
	var real_junctions:=_junction_plan(graph_data)
	var junctions: Dictionary={}; var visible_edges: Dictionary={}; var root:=KiwiModelComponent.new(); root.id=source.world_id; root.title="World"; root.parameters.world_source=source; root.parameters.world_graph=graph_data; document.components.append(root)
	for edge: Dictionary in graph_data.edges:
		if cancel.is_valid() and cancel.call(): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
		var start: float=float(edge.width) if real_junctions.has(edge.from) else 0.; var end: float=float(edge.width) if real_junctions.has(edge.to) else 0.; var points:=Geometry.trim(edge.points,start,end)
		var section=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd"); var section_source:=edge.duplicate(); section_source.distance_start=float(edge.get("distance_start",0.))+start; var generated: Dictionary=section.build(points,section_source,cancel)
		if generated.get("cancelled",false): return {"cancelled":true,"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray()}
		if not generated.errors.is_empty(): return {"document":null,"errors":generated.errors,"warnings":PackedStringArray()}
		var mesh: KiwiModelMesh=generated.surface; var id:=str(source.world_id)+":road:"+str(edge.id); var item:=_item(document,id,str(edge.get("name","Road")),root.id,mesh,section.material(source,edge)); item.parameters.world_road=edge.id; var midpoint: Vector3=points[points.size()/2]; item.parameters.world_region=source.region_at(Vector2(midpoint.x,midpoint.z)); item.parameters.road_type=edge.get("type","Residential Street")
		if edge.has("connection"): item.parameters.world_connection=edge.connection
		for region: Dictionary in source.regions:
			if region.id==item.parameters.world_region: item.visible=region.get("enabled",true)
		item.parameters.world_generated_visible=item.visible; visible_edges[edge.id]=item.visible
		var mode:=str(edge.get("mode","Ground"))
		for detail: String in ["shoulders","sidewalks","curbs","markings"]:
			if not generated.has(detail): continue
			# Bridge railings occupy the sidewalk space; tunnels use their excavated
			# road section without exterior pavements intersecting the cave walls.
			if mode!="Ground" and detail!="markings": continue
			var child:=_item(document,id+":"+detail,detail.capitalize(),item.id,generated[detail],section.material(source,edge,detail),root.id); child.visible=item.visible; child.parameters.world_generated_visible=child.visible; child.parameters.world_region=item.parameters.world_region; child.parameters.road_detail=detail
		if mode=="Bridge":
			var ground: Callable=func(point: Vector2): return source.terrain_field.sample(point) if source.terrain_field!=null else {}
			var structure:=preload("res://Workspaces/EnvironmentWorkspace/world/road_structures.gd").bridge(points,float(edge.width),float(edge.get("pier_height",8.)),ground if edge.get("auto_piers",false) else Callable(),edge.get("_cross_sections",{}))
			item.mesh=structure.deck; item.parameters.world_mesh_key=hash([item.mesh.vertices,item.mesh.faces])
			for part: String in ["railings","supports"]:
				if structure[part].faces.is_empty(): continue
				var child:=_item(document,id+":"+part,part.capitalize(),item.id,structure[part],source.shoulder_material if source.shoulder_material!=null else source.road_material,root.id); child.visible=item.visible; child.parameters.world_generated_visible=child.visible; child.parameters.world_region=item.parameters.world_region
		for side in 2:
			var node_id: String=edge.from if side==0 else edge.to
			if not real_junctions.has(node_id): continue
			if not junctions.has(node_id): junctions[node_id]=[]
			var point: Vector3=points[0] if side==0 else points[-1]; var direction: Vector3=(points[1]-points[0]).normalized() if side==0 else (points[-2]-points[-1]).normalized(); junctions[node_id].append({"point":point,"direction":direction,"width":edge.width,"road":edge})
	for id: String in junctions:
		var mesh:=Geometry.junction(graph_data.nodes[id],junctions[id]); var item:=_item(document,str(source.world_id)+":junction:"+id,"Junction",root.id,mesh,source.road_material); item.visible=false
		for edge_id in graph_data.adjacency[id]: item.visible=item.visible or visible_edges.get(edge_id,false)
		item.parameters.world_generated_visible=item.visible
		var details:=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").junction_details(junctions[id])
		for detail in details:
			var child:=_item(document,item.id+":"+str(detail),"Junction "+str(detail),item.id,details[detail],preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").material(source,{},str(detail)),root.id); child.visible=item.visible; child.parameters.world_generated_visible=child.visible; child.parameters.road_detail=detail
	for road: Dictionary in source.roads:
		if not road.get("enabled",true) or str(road.get("mode","Ground"))!="Tunnel": continue
		var points: PackedVector3Array=road.get("portal_points",road.points)
		var portals:=preload("res://Workspaces/EnvironmentWorkspace/world/road_structures.gd").portals(points,float(road.width),true,true,road.get("portal_frames",[])); _item(document,str(source.world_id)+":portals:"+str(road.id),"Tunnel portals",root.id,portals,source.shoulder_material if source.shoulder_material!=null else source.road_material)
	var architecture:=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd").build(document,source,settlement_layout,cancel)
	if architecture.get("cancelled",false): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	var forests:=_populate(document,source,settlement_layout,graph_data,cancel)
	if forests.get("cancelled",false): return {"document":null,"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	forests.settings.merge(architecture.get("settings",{}),true)
	errors.append_array(architecture.errors); errors.append_array(forests.errors); errors.append_array(document.validate()); var warnings: PackedStringArray=graph_data.warnings; warnings.append_array(settlement_layout.warnings); warnings.append_array(architecture.warnings); warnings.append_array(forests.warnings); root.parameters.world_plots=settlement_layout.plots; root.parameters.world_blocks=settlement_layout.blocks; root.parameters.world_connections=settlement_layout.connections
	return {"document":document if errors.is_empty() else null,"errors":errors,"warnings":warnings,"settings":forests.settings}
static func _populate(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph_data: Dictionary,cancel: Callable) -> Dictionary:
	var forests:=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").build(document,source,layout,graph_data,cancel)
	if forests.get("cancelled",false): return forests
	var props:=preload("res://Workspaces/EnvironmentWorkspace/world/world_props.gd").build(document,source,layout,graph_data,cancel)
	if props.get("cancelled",false): return props
	forests.settings.merge(props.settings); forests.errors.append_array(props.errors); forests.warnings.append_array(props.warnings); return forests
static func _junction_plan(graph_data: Dictionary) -> Dictionary:
	var edges: Dictionary={}; var junctions: Dictionary={}
	for edge: Dictionary in graph_data.edges: edges[edge.id]=edge; edge._cross_sections={}
	for node in graph_data.adjacency:
		var adjacent: Array=graph_data.adjacency[node]
		if adjacent.size()<2: continue
		if adjacent.size()!=2: junctions[node]=true; continue
		var a: Dictionary=edges[adjacent[0]]; var b: Dictionary=edges[adjacent[1]]; var directions: Array[Vector3]=[]
		for edge: Dictionary in [a,b]:
			var points: PackedVector3Array=edge.points; var direction: Vector3=points[1]-points[0] if edge.from==node else points[-2]-points[-1]; direction.y=0.; directions.append(direction.normalized())
		if directions[0].dot(directions[1])>-.95 or not is_equal_approx(float(a.width),float(b.width)) or not is_equal_approx(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(a),preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(b)):
			junctions[node]=true; continue
		for index in 2:
			var edge: Dictionary=a if index==0 else b; var away: Vector3=(directions[index]-directions[1-index]).normalized(); var tangent:=away if edge.from==node else -away; var side:=Vector3(-tangent.z,0.,tangent.x); var local_side:=Vector3(-directions[index].z,0.,directions[index].x); side/=maxf(.5,absf(side.dot(local_side))); edge._cross_sections["start" if edge.from==node else "end"]=side
	return junctions
static func _item(document: KiwiModelDocument,id: String,title: String,parent: String,mesh: KiwiModelMesh,material: Material,owner: String="") -> KiwiModelComponent:
	if owner.is_empty(): owner=parent
	var item:=KiwiModelComponent.new(); item.id=id; item.title=title; item.parent_id=parent; item.mesh=mesh; item.surface_materials=[material]; item.parameters.world_generated=true; item.parameters.world_owner=owner; item.parameters.world_key=id.trim_prefix(owner); item.parameters.world_pose=item.transform; item.parameters.world_structure=item.structural.duplicate(true); item.parameters.world_materials=item.surface_materials.duplicate(); item.parameters.world_mesh_key=hash([mesh.vertices,mesh.faces]); document.components.append(item); return item
