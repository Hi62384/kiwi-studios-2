extends RefCounted
## Settlement sources derive streets and frontage plots before any buildings.
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
const Spatial=preload("res://Workspaces/EnvironmentWorkspace/world/world_spatial_index.gd")
static func create(source: Resource,center: Vector3,profile: String="Town") -> Resource:
	var next: Resource=source.copy(); var id:=ActorData.new_id(); var template: Resource=Buildings.rectangular(); template=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").apply(template,"Cottage" if profile=="Village" else "Modern")
	var radius:=clampf(minf(source.dimensions.x,source.dimensions.y)*.4,8.,48.); var road_width:=8. if profile=="City" and radius>=24. else 5.; var blocks:=clampi(floori(radius*2./(road_width+12.)),1,3)
	next.settlements.append({"id":id,"name":profile+" "+str(next.settlements.size()+1),"profile":profile,"center":center,"radius":radius,"blocks":blocks,"seed":hash([source.seed,id]),"enabled":true,"locked":false,"template":template,"height_min":1,"height_max":2 if profile!="City" else 6,"setback":2.})
	return next
static func layout(source: Resource,cancel: Callable=Callable()) -> Dictionary:
	var nodes: Dictionary={}; var roads: Array[Dictionary]=[]; var plots: Array[Dictionary]=[]; var blocks: Array[Dictionary]=[]; var warnings:=PackedStringArray()
	for settlement: Dictionary in source.settlements:
		if not settlement.get("enabled",true): continue
		if str(settlement.get("layout_mode","Grid"))=="Road network": continue
		var prefix:=str(settlement.id); var center: Vector3=settlement.center; var radius:=float(settlement.get("radius",48.)); var rng:=RandomNumberGenerator.new(); rng.seed=int(settlement.get("seed",1)); var profile:=str(settlement.get("profile","Town"))
		if profile=="Village":
			var spokes:=5
			for spoke in spokes:
				var angle:=TAU*spoke/spokes+rng.randf_range(-.18,.18); var direction:=Vector3(cos(angle),0.,sin(angle)); var side:=Vector3(-direction.z,0.,direction.x); var end:=center+direction*radius*rng.randf_range(.8,1.); var start_id:=prefix+":center"; var end_id:=prefix+":end:"+str(spoke); nodes[start_id]=center; nodes[end_id]=end; var road_id:=prefix+":lane:"+str(spoke); roads.append(_road(road_id,start_id,end_id,PackedVector3Array([center,center.lerp(end,.5)+side*rng.randf_range(-3.,3.),end]),3.,prefix))
				for row in 2:
					for sign: float in [-1.,1.]:
						var depth:=rng.randf_range(7.,10.); var width:=rng.randf_range(6.,9.); var position:=center+direction*radius*(.38+row*.35)+side*sign*(depth*.5+4.); var facing: Vector3=-side*sign; var pose:=Transform3D(Basis.looking_at(facing,Vector3.UP),position); var id:=prefix+":plot:"+str(spoke)+":"+str(row)+":"+str(sign); var polygon:=_rectangle(pose,width+2.,depth+2.); plots.append({"id":id,"settlement":prefix,"block":"","polygon":polygon,"pose":pose,"width":width,"depth":depth,"frontage":road_id,"district":"Rural","reserved":false})
		else:
			var count:=clampi(int(settlement.get("blocks",3)),1,6); var step:=radius*2./count; var road_width:=8. if profile=="City" and radius>=24. else 5.
			for line in count+1:
				for axis in 2:
					var a:=center+Vector3(-radius,0.,-radius); var b:=a
					if axis==0: a.x+=step*line; b=Vector3(a.x,center.y,center.z+radius)
					else: a.z+=step*line; b=Vector3(center.x+radius,center.y,a.z)
					var road_id:=prefix+":street:"+str(axis)+":"+str(line); var from:=road_id+":a"; var to:=road_id+":b"; nodes[from]=a; nodes[to]=b; roads.append(_road(road_id,from,to,PackedVector3Array([a,b]),road_width,prefix))
			for z in count:
				for x in count:
					var position:=center+Vector3(-radius+step*(x+.5),0.,-radius+step*(z+.5)); var block_id:=prefix+":block:"+str(x)+":"+str(z); var usable:=step-road_width-2.*float(settlement.get("setback",2.)); var district: String="Downtown" if profile=="City" and x==count/2 and z==count/2 else ("Industrial" if profile=="City" and z==count-1 else "Residential")
					if usable<6.: warnings.append(str(settlement.get("name",prefix))+": blocks are too small for usable buildings."); continue
					var pose:=Transform3D(Basis.IDENTITY,position); var polygon:=_rectangle(pose,usable,usable); blocks.append({"id":block_id,"settlement":prefix,"polygon":polygon,"district":district})
					plots.append({"id":block_id+":plot","settlement":prefix,"block":block_id,"polygon":polygon,"pose":pose,"width":usable*rng.randf_range(.65,.85),"depth":usable*rng.randf_range(.65,.85),"frontage":prefix+":street:1:"+str(z),"district":district,"reserved":false})
	for road: Dictionary in roads:
		for settlement: Dictionary in source.settlements:
			if str(road.get("settlement",""))!=str(settlement.id) or not settlement.has("road_type"): continue
			var width:=float(road.width); road.merge(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").defaults(str(settlement.road_type)),true); road.width=width
	if source.terrain_field!=null:
		for road: Dictionary in roads:
			var points:=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd").sample(road.points,2.); var usable:=true
			for index in points.size():
				var point:=points[index]; var surface: Dictionary=source.terrain_field.sample(Vector2(point.x,point.z))
				if surface.is_empty() or surface.get("water",false): usable=false; break
				point.y=float(surface.height)+.03; points[index]=point
				if index>0:
					var horizontal:=Vector2(point.x,point.z).distance_to(Vector2(points[index-1].x,points[index-1].z))
					if absf(point.y-points[index-1].y)/maxf(.01,horizontal)>.2: usable=false; break
			road.enabled=usable
			if usable: road.points=points; nodes[road.from]=points[0]; nodes[road.to]=points[-1]
			else: warnings.append("Street "+str(road.id)+" leaves the terrain, crosses water or exceeds its grade limit.")
	var claimed: Dictionary={}
	for settlement: Dictionary in source.settlements:
		if not settlement.get("enabled",true) or str(settlement.get("layout_mode","Grid"))!="Road network": continue
		var graph: Dictionary=load("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").graph(source,cancel,{"nodes":nodes,"roads":roads})
		if graph.get("cancelled",false): return {"cancelled":true}
		if graph.has("errors"): warnings.append_array(graph.errors); continue
		var generated:=preload("res://Workspaces/EnvironmentWorkspace/world/world_blocks.gd").extract(graph,cancel)
		if generated.get("cancelled",false): return {"cancelled":true}
		warnings.append_array(generated.warnings); var center: Vector3=settlement.center; var radius:=float(settlement.radius); var region:=Rect2(Vector2(center.x,center.z)-Vector2.ONE*radius,Vector2.ONE*radius*2.); var count:=0; var usable_blocks:=0
		for block: Dictionary in generated.blocks:
			if claimed.has(block.id) or not region.encloses(preload("res://Workspaces/EnvironmentWorkspace/world/world_blocks.gd")._bounds(block.polygon)): continue
			claimed[block.id]=true; block.settlement=settlement.id; block.district="Residential"; var settings:=Districts.rules(block,settlement); blocks.append(block)
			usable_blocks+=1
			if float(settings.get("density",1.))<=0.: continue
			var lots:=preload("res://Workspaces/EnvironmentWorkspace/world/world_blocks.gd").plots(block,Districts.effective(settlement,settings),maxi(0,int(source.max_building_plots)-plots.size()),cancel)
			for plot: Dictionary in lots:
				if not Districts.accept(plot,settings): continue
				plot.district=block.district; plot.district_id=block.get("district_id",""); plot.generation=settings; plots.append(plot); count+=1
		if usable_blocks==0: warnings.append(str(settlement.get("name","Settlement"))+": no usable bounded ground-road blocks fit this area. Draw a closed road network or enlarge the settlement radius.")
	var connections:=preload("res://Workspaces/EnvironmentWorkspace/world/world_connections.gd").augment(source,nodes,roads,cancel)
	if connections.get("cancelled",false): return {"cancelled":true}
	warnings.append_array(connections.warnings)
	var all_roads: Array=source.roads.duplicate(); all_roads.append_array(roads); var accepted: Array[Dictionary]=[]
	var road_index:=Spatial.new(); var masks:=Spatial.new(); var plot_index:=Spatial.new(); var frontage_index: Dictionary={}; var samples:=0
	for road: Dictionary in all_roads:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		frontage_index[str(road.id)]=road
		if not road.get("enabled",true): continue
		var points:=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd").sample(road.points); samples+=points.size()
		if samples>65536: return {"nodes":nodes,"roads":roads,"plots":[],"blocks":blocks,"warnings":warnings,"connections":connections.connections,"errors":PackedStringArray(["Settlement road sampling exceeds 65,536 points. Simplify roads or generate a smaller region."])}
		var polygon:=PackedVector2Array()
		for point in points: polygon.append(Vector2(point.x,point.z))
		road_index.add(Spatial.polygon_bounds(polygon).grow(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(road)+.1),{"road":road,"points":points})
	for area: Dictionary in source.exclusions:
		if area.get("protected",true) and area.get("polygon",PackedVector2Array()).size()>=3: masks.add(Spatial.polygon_bounds(area.polygon),area)
	for area: Dictionary in source.occupied: masks.add(Spatial.polygon_bounds(area.polygon),area)
	for plot: Dictionary in plots:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		if not plot.has("generation"):
			for settlement: Dictionary in source.settlements:
				if settlement.id!=plot.settlement: continue
				var block: Dictionary={"id":plot.block,"polygon":plot.polygon,"district":plot.district}
				var settings:=Districts.rules(block,settlement); plot.district=block.district; plot.district_id=block.get("district_id",""); plot.generation=settings
				if not settings.is_empty():
					var limit:=maxf(4.,float(settings.get("lot_size",64.))-2.*float(settings.get("setback",0.))); plot.width=minf(float(plot.width),limit); plot.depth=minf(float(plot.depth),limit)
				for stored: Dictionary in blocks:
					if stored.id==plot.block: stored.district=block.district; stored.district_id=block.get("district_id","")
				break
		if not Districts.accept(plot,plot.get("generation",{})): continue
		var blocked:=false; var bounds:=Spatial.polygon_bounds(plot.polygon); var frontage: Dictionary=frontage_index.get(str(plot.frontage),{})
		if frontage.is_empty() or not frontage.get("enabled",true): continue
		if source.terrain_field!=null:
			var maximum:=-INF; var minimum:=INF; var pose: Transform3D=plot.pose; var terrain_ok:=true
			for z in 3:
				for x in 3:
					var point:=pose*Vector3((float(x)*.5-.5)*float(plot.width),0.,(float(z)*.5-.5)*float(plot.depth)); var surface: Dictionary=source.terrain_field.sample(Vector2(point.x,point.z))
					if surface.is_empty() or surface.get("water",false) or (surface.normal as Vector3).y<.94: terrain_ok=false; continue
					maximum=maxf(maximum,float(surface.height)); minimum=minf(minimum,float(surface.height))
			if not terrain_ok or maximum-minimum>1.2: warnings.append("Plot "+str(plot.id)+" has unsuitable terrain or slope."); continue
			var door:=pose*Vector3(0.,0.,-float(plot.depth)*.5); var access:=_road_access(door,frontage)
			if not access.is_empty(): maximum=maxf(maximum,(access.position as Vector3).y)
			pose.origin.y=maximum+.15; plot.pose=pose; plot.foundation_depth=maxf(.4,maximum-minimum+.4)
		for area: Dictionary in masks.query(bounds):
			if str(area.get("world",""))==str(source.world_id) and str(area.get("plot",""))==str(plot.id): continue
			if not Geometry2D.intersect_polygons(plot.polygon,area.polygon).is_empty(): blocked=true; break
		if not blocked:
			for previous: Dictionary in plot_index.query(bounds):
				if not Geometry2D.intersect_polygons(plot.polygon,previous.polygon).is_empty(): blocked=true; break
		if not blocked:
			for candidate: Dictionary in road_index.query(bounds):
				if _overlaps_road(plot.polygon,candidate.road,candidate.points): blocked=true; break
		if not blocked:
			accepted.append(plot); plot_index.add(bounds,plot)
			if accepted.size()>=int(source.max_building_plots): warnings.append("World plot budget reached; increase the budget to populate more frontage."); break
	return {"nodes":nodes,"roads":roads,"plots":accepted,"blocks":blocks,"warnings":warnings,"connections":connections.connections}
static func _overlaps_road(polygon: PackedVector2Array,road: Dictionary,points: PackedVector3Array=PackedVector3Array()) -> bool:
	if points.is_empty(): points=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd").sample(road.points)
	for segment in points.size()-1:
		var a:=Vector2(points[segment].x,points[segment].z); var b:=Vector2(points[segment+1].x,points[segment+1].z)
		if Geometry2D.is_point_in_polygon(a,polygon): return true
		for edge in polygon.size():
			var c:=polygon[edge]; var d:=polygon[(edge+1)%polygon.size()]
			if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return true
			var distance:=minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))),minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)),d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))))
			if distance<preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(road)+.05: return true
	return false
static func _road_access(door: Vector3,road: Dictionary) -> Dictionary:
	if road.is_empty(): return {}
	var points: PackedVector3Array=road.points; var best:=INF; var position:=Vector3.ZERO
	for segment in points.size()-1:
		var a:=Vector2(points[segment].x,points[segment].z); var b:=Vector2(points[segment+1].x,points[segment+1].z); var closest:=Geometry2D.get_closest_point_to_segment(Vector2(door.x,door.z),a,b); var distance:=closest.distance_to(Vector2(door.x,door.z))
		if distance>=best: continue
		best=distance; var t:=a.distance_to(closest)/maxf(.001,a.distance_to(b)); position=points[segment].lerp(points[segment+1],t)
	var direction:=Vector3(door.x-position.x,0.,door.z-position.z).normalized(); position+=direction*float(road.width)*.5
	return {"position":position,"direction":direction}
static func build(document: KiwiModelDocument,source: Resource,generated: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var warnings:=PackedStringArray(); var errors:=PackedStringArray(); var count:=0; var settings: Dictionary={}
	for settlement: Dictionary in source.settlements:
		if not settlement.get("enabled",true): continue
		var group:=_group(document,str(source.world_id)+":settlement:"+str(settlement.id),str(settlement.get("name","Settlement")),source.world_id,source.world_id); group.parameters.world_settlement=settlement.id
		for plot: Dictionary in generated.plots:
			if plot.settlement!=settlement.id: continue
			var plot_settings:=Districts.effective(settlement,plot.get("generation",{})); var template: Resource=plot_settings.get("template")
			if template==null: errors.append("Settlement "+str(settlement.id)+" has no architectural template."); continue
			if cancel.is_valid() and cancel.call(): return {"errors":errors,"warnings":warnings,"cancelled":true}
			var plot_group:=_group(document,str(source.world_id)+":plot:"+str(plot.id),str(plot.district)+" plot",group.id,source.world_id); plot_group.parameters.world_plot=plot.id; plot_group.parameters.polygon=plot.polygon
			var position: Vector3=(plot.pose as Transform3D).origin; var region_id: String=source.region_at(Vector2(position.x,position.z)); var enabled:=true
			for region: Dictionary in source.regions:
				if region.id==region_id: enabled=bool(region.get("enabled",true))
			plot_group.visible=enabled; plot_group.parameters.world_region=region_id; plot_group.parameters.world_generated_visible=enabled
			if source.plot_overrides.get(plot.id,{}).get("reserved",false): continue
			if count>=int(source.max_building_plots): warnings.append("World building-plot budget reached. Increase the plot budget or reduce layout density."); break
			var rng:=RandomNumberGenerator.new(); rng.seed=hash([plot_settings.get("seed",1),plot.id]); var maximum:=clampi(int(plot_settings.get("height_max",2)),1,8)
			if plot.get("generation",{}).is_empty():
				if plot.district in ["Residential","Rural"]: maximum=mini(2,maximum)
				if plot.district=="Industrial": maximum=1
			var minimum:=clampi(int(plot_settings.get("height_min",1)),1,maximum)
			if plot.district=="Downtown" and maximum>=3: minimum=maxi(3,minimum)
			var levels:=rng.randi_range(minimum,maximum); var authored: Resource=Buildings.rectangular(float(plot.width),float(plot.depth),levels,false); authored.source_id=str(source.world_id)+":building:"+str(plot.id); authored.seed=rng.randi(); authored.materials.assign(template.materials); authored.style=template.style; authored.wall_thickness=template.wall_thickness; authored.roof_type=0 if plot.district=="Downtown" else (2 if plot.district=="Industrial" else rng.randi_range(1,3)); authored.roof_pitch=rng.randf_range(20.,45.); authored.facade_detail=template.facade_detail
			if plot.district=="Industrial":
				authored.floors[0].height=3.6; authored.floors[0].walls[0].openings[0].width=minf(2.8,float(plot.width)*.6); authored.floors[0].walls[0].openings[0].height=2.8; authored.facade_detail=6
			for level in levels-1: authored.stairs.append({"id":"core:"+str(level),"from":authored.floors[level].id,"to":authored.floors[level+1].id,"type":0,"position":Vector2(-float(plot.width)*.35,-float(plot.depth)*.3),"width":.9,"length":minf(4.,float(plot.depth)-2.),"steps":18})
			authored.foundation_depth=float(plot.get("foundation_depth",.4))
			if count>=int(source.eager_building_limit):
				var lazy:=KiwiModelComponent.new(); lazy.id=authored.source_id; lazy.parent_id=plot_group.id; lazy.title=authored.title; lazy.transform=plot.pose; lazy.mesh=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_massing.gd").mesh(authored); lazy.surface_materials.assign(authored.materials); lazy.parameters={"architecture_source":authored,"architecture_type":"building","architecture_owner":lazy.id,"architecture_key":"","world_lazy_building":true,"world_owner":source.world_id,"world_generated":true,"world_key":lazy.id.trim_prefix(str(source.world_id)),"world_pose":lazy.transform,"world_plot":plot.id,"world_region":region_id,"world_generated_visible":enabled,"world_materials":lazy.surface_materials.duplicate(),"world_structure":{},"world_architecture_source_key":preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(authored)}; lazy.visible=enabled; preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._mark(lazy); document.components.append(lazy); settings[lazy.id]={"kind":"building","collision":true}; count+=1; continue
			var output:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd").generate(authored,cancel)
			if output.get("cancelled",false): return {"errors":errors,"warnings":warnings,"cancelled":true}
			if output.document==null or not output.errors.is_empty(): errors.append_array(output.errors); continue
			for item: KiwiModelComponent in output.document.components:
				if item.id==authored.source_id: item.parent_id=plot_group.id; item.transform=plot.pose
				preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._mark(item); item.parameters.world_generated=true; item.parameters.world_owner=source.world_id; item.parameters.world_key=item.id.trim_prefix(str(source.world_id)); item.parameters.world_pose=item.transform; item.parameters.world_mesh_key=hash([item.mesh.vertices,item.mesh.faces]) if item.mesh!=null else 0; item.parameters.world_plot=plot.id; item.parameters.world_generated_visible=item.visible; item.parameters.world_materials=item.surface_materials.duplicate(); item.parameters.world_structure=item.structural.duplicate(true)
				if item.parameters.has("architecture_source"): item.parameters.world_architecture_source_key=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(authored)
				item.parameters.world_region=region_id
				document.components.append(item)
			if source.terrain_field!=null:
				var frontage: Dictionary={}
				var frontage_roads: Array=source.roads.duplicate(); frontage_roads.append_array(generated.roads)
				for road: Dictionary in frontage_roads:
					if road.id==plot.frontage: frontage=road; break
				var entry:=_entry(authored,plot,frontage,source.world_id)
				if entry!=null: document.components.append(entry)
			count+=1
	return {"errors":errors,"warnings":warnings,"settings":settings}
static func _entry(authored: Resource,plot: Dictionary,road: Dictionary,world_id: String) -> KiwiModelComponent:
	var pose: Transform3D=plot.pose; var door:=pose*Vector3(0.,0.,-float(plot.depth)*.5); var access:=_road_access(door,road)
	if access.is_empty(): return null
	var origin: Vector3=access.position; var difference:=door-origin; var rise:=difference.y; difference.y=0.; var run:=difference.length()
	if run<.1 or rise<-.05 or rise>2.: return null
	var mesh:=KiwiModelMesh.new(); var steps:=clampi(ceili(maxf(0.,rise)/.18),1,12); var footing:=.3; var basis:=Basis.looking_at(-difference.normalized(),Vector3.UP)
	for step in steps:
		var top:=maxf(.02,rise*float(step+1)/steps); mesh.append_mesh(KiwiModelPrimitives.box(Vector3(1.2,top+footing,run/steps+.005)),Transform3D(Basis.IDENTITY,Vector3(0.,(top-footing)*.5,run*(step+.5)/steps)))
	var item:=KiwiModelComponent.new(); item.id=str(authored.source_id)+":entry"; item.title="Entrance steps"; item.parent_id=authored.source_id; item.mesh=mesh; item.transform=pose.affine_inverse()*Transform3D(basis,origin); item.surface_materials=[authored.materials[0]]; item.parameters={"world_generated":true,"world_owner":world_id,"world_key":item.id.trim_prefix(world_id),"world_pose":item.transform,"world_mesh_key":hash([mesh.vertices,mesh.faces]),"world_plot":plot.id,"architecture_type":"entry stairs","world_materials":item.surface_materials.duplicate(),"world_structure":{}}; return item
static func _group(document: KiwiModelDocument,id: String,title: String,parent: String,owner: String) -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=id; item.title=title; item.parent_id=parent; item.parameters={"world_generated":true,"world_owner":owner,"world_key":id.trim_prefix(owner),"world_mesh_key":0,"world_pose":Transform3D.IDENTITY}; document.components.append(item); return item
static func _road(id: String,from: String,to: String,points: PackedVector3Array,width: float,settlement: String) -> Dictionary:
	var road:=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").defaults("Rural Road" if width<=3. else "Residential Street"); road.merge({"id":id,"name":"Street","from":from,"to":to,"points":points,"width":width,"enabled":true,"mode":"Ground","settlement":settlement},true); return road
static func _rectangle(pose: Transform3D,width: float,depth: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]: var p:=pose*Vector3(corner.x*width*.5,0.,corner.y*depth*.5); result.append(Vector2(p.x,p.z))
	return result
