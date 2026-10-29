extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
static func find(source: Resource,index: int,cancel: Callable=Callable()) -> Dictionary:
	if source.terrain_field==null or index<0 or index>=source.settlements.size(): return {"error":"Choose a terrain and settlement before finding a site."}
	var settlement: Dictionary=source.settlements[index]; var radius:=float(settlement.radius); var margin:=radius+8.; var bounds:=Rect2(-source.dimensions*.5+Vector2.ONE*margin,source.dimensions-Vector2.ONE*margin*2.)
	if bounds.size.x<=0. or bounds.size.y<=0.: return {"error":"This settlement is too large for the world. Reduce its radius or enlarge the world."}
	var masks: Array=[]
	for area: Dictionary in source.exclusions+source.occupied:
		if not area.get("protected",true): continue
		var polygon: PackedVector2Array=area.get("polygon",PackedVector2Array())
		if polygon.size()<3: continue
		var rectangle:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: rectangle=rectangle.expand(point)
		masks.append({"bounds":rectangle,"polygon":polygon})
	var best:=INF; var chosen:=Vector3.ZERO; var found:=false; var rng:=RandomNumberGenerator.new(); rng.seed=int(settlement.get("seed",source.seed)); var preferred: Vector3=settlement.center; var field: RefCounted=source.terrain_field
	for z in 17:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true,"error":"Site search canceled."}
		for x in 17:
			var center:=bounds.position+Vector2(x,z)/16.*bounds.size; var footprint:=Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.); var blocked:=false
			for other in source.settlements.size():
				if other==index or not source.settlements[other].get("enabled",true): continue
				var point: Vector3=source.settlements[other].center
				var other_radius:=float(source.settlements[other].radius); var other_bounds:=Rect2(Vector2(point.x,point.z)-Vector2.ONE*other_radius,Vector2.ONE*other_radius*2.)
				if footprint.grow(6.).intersects(other_bounds.grow(6.)): blocked=true; break
			if blocked: continue
			for region: Dictionary in source.regions:
				if region.get("locked",false) and (region.bounds as Rect2).intersects(footprint): blocked=true; break
			if blocked: continue
			var rectangle:=PackedVector2Array([footprint.position,Vector2(footprint.end.x,footprint.position.y),footprint.end,Vector2(footprint.position.x,footprint.end.y)])
			for mask_index in masks.size():
				if mask_index%64==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true,"error":"Site search canceled."}
				var mask: Dictionary=masks[mask_index]
				if (mask.bounds as Rect2).intersects(footprint) and not Geometry2D.intersect_polygons(rectangle,mask.polygon).is_empty(): blocked=true; break
			if blocked: continue
			var low:=INF; var high:=-INF; var slope:=0.; var height:=0.
			for sz in 3:
				for sx in 3:
					var point:=center+Vector2(sx-1,sz-1)*radius; var surface: Dictionary=field.sample(point)
					if surface.is_empty() or surface.get("water",false) or (surface.normal as Vector3).y<.97: blocked=true; break
					var value:=float(surface.height); low=minf(low,value); high=maxf(high,value); height+=value/9.; slope+=1.-float((surface.normal as Vector3).y)
				if blocked: break
			if blocked or high-low>maxf(.5,radius*.12): continue
			var score:=slope*30.+(high-low)*2.+center.distance_to(Vector2(preferred.x,preferred.z))/maxf(1.,source.dimensions.length())+rng.randf()*.02
			if not source.nodes.is_empty():
				var road_distance:=INF
				for node in source.nodes.values(): road_distance=minf(road_distance,center.distance_to(Vector2(node.x,node.z)))
				score+=road_distance/maxf(1.,source.dimensions.length())*.5
			if field.water_resolution>0:
				var water_access:=1.
				for direction in 8:
					var surface: Dictionary=field.sample(center+Vector2.from_angle(direction*TAU/8.)*radius*1.5)
					if surface.get("water",false): water_access=0.; break
				score+=water_access*.2
			if score<best: best=score; chosen=Vector3(center.x,height,center.y); found=true
	return {"position":chosen,"score":best,"error":"" if found else "No dry, sufficiently flat site fits the settlement and its clearance. Reduce its radius or edit the terrain and exclusion masks."}
static func request(workspace: Control,id: String,index: int=-1,profile: String="") -> void:
	var session: KiwiEnvironmentSession=workspace.session; var tree:=workspace.get_tree(); var selected_id:=""
	if index>=0:
		var current: Resource=Edit.source(session,id)
		if current==null or index>=current.settlements.size(): return
		selected_id=current.settlements[index].id
	if not await Edit.flush(session) or not is_instance_valid(workspace) or workspace.session!=session: return
	var authored: Resource=Edit.source(session,id)
	if authored==null: return
	authored=authored.copy()
	if not profile.is_empty():
		authored=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd").create(authored,Vector3.ZERO,profile); index=authored.settlements.size()-1; authored.settlements[index].radius=minf(float(authored.settlements[index].radius),maxf(8.,minf(authored.dimensions.x,authored.dimensions.y)*.12))
	else:
		index=-1
		for candidate in authored.settlements.size():
			if str(authored.settlements[candidate].id)==selected_id: index=candidate; break
	if index<0: return
	var field:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").capture(session,id,authored)
	if not str(field.error).is_empty(): workspace.status.text=field.error; return
	authored.terrain_field=field.field; var error:=preload("res://Workspaces/EnvironmentWorkspace/world/world_occupancy.gd").capture(session,id,authored)
	if not error.is_empty(): workspace.status.text=error; return
	if session.pending_source_cancel.is_valid(): workspace.status.text="Finish the current source edit before finding a settlement site."; return
	var revision:=session.revision; var document:=session.document; var job: RefCounted=load("res://Workspaces/EnvironmentWorkspace/world/world_site_job.gd").new(); workspace.set_meta("world_site_job",job); session.pending_source_cancel=job.cancel; workspace.status.text="Finding a settlement site…"; job.start(authored,index)
	while not job.complete():
		if not is_instance_valid(workspace) or workspace.session!=session or session.document!=document or session.revision!=revision: job.cancel()
		await tree.process_frame
	var result: Dictionary=job.collect()
	if session.pending_source_cancel==job.cancel: session.pending_source_cancel=Callable()
	if not is_instance_valid(workspace): return
	if workspace.has_meta("world_site_job") and workspace.get_meta("world_site_job")==job: workspace.remove_meta("world_site_job")
	if workspace.session!=session or session.document!=document or session.revision!=revision or job.cancelled(): return
	if not str(result.get("error","")).is_empty(): workspace.status.text=result.error; return
	authored.settlements[index].center=result.position; workspace.set_meta("world_section",2); workspace.set_meta("world_settlement_index",index); var applied:=await Edit.request(session,id,authored,"Place settlement on suitable terrain")
	if is_instance_valid(workspace) and workspace.session==session: workspace.status.text=applied.errors[0] if not applied.errors.is_empty() else "Settlement placed"
