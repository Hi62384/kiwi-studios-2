extends RefCounted
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const MODES=["Roadside","Region","Clusters","Grid","Anchors"]
static func create(source: Resource,model: Variant,mode: String="Roadside") -> Resource:
	var next: Resource=source.copy(); var title: String=model.components[0].title if model is KiwiModelDocument and not model.components.is_empty() else str(model).get_file().get_basename()
	next.prop_rules.append({"id":ActorData.new_id(),"name":title,"mode":mode,"model":model,"spacing":12.,"setback":2.,"sides":"Both","seed":source.seed,"bounds":Rect2(-source.dimensions*.45,source.dimensions*.9),"density":.02,"budget":2000,"yaw":0.,"scale_range":Vector2.ONE,"enabled":true,"collisions":false,"biome_ids":PackedStringArray(),"slope_range":Vector2(0,40),"height_range":Vector2(-10000,10000),"anchors":[]}); return next
static func build(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var settings: Dictionary={}; var warnings:=PackedStringArray(); var errors:=PackedStringArray()
	if source.prop_rules.is_empty(): return {"settings":settings,"warnings":warnings,"errors":errors}
	if source.terrain_field==null: return {"settings":settings,"warnings":warnings,"errors":PackedStringArray(["Choose a terrain before populating objects."])}
	var field: RefCounted=source.terrain_field
	for rule: Dictionary in source.prop_rules:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		if not rule.get("enabled",true): continue
		var rules:=KiwiEnvironmentScatter.new(); rules.terrain_id=source.terrain_id; rules.palette=[{"source":rule.model,"weight":1.}]; rules.seed=int(rule.seed); rules.density=clampf(float(rule.get("density",.02)),0.,100.); rules.budget=clampi(int(rule.get("budget",2000)),1,20000); rules.minimum_distance=float(rule.spacing)*.5; rules.scale_range=rule.get("scale_range",Vector2.ONE); rules.yaw_range=Vector2.ONE*float(rule.get("yaw",0.)); rules.align_normal=false; rules.collisions=bool(rule.get("collisions",false)); rules.slope_range=rule.get("slope_range",Vector2(0,40)); rules.height_range=rule.get("height_range",Vector2(-10000,10000)); rules.biome_ids=rule.get("biome_ids",PackedStringArray()); rules.exclude_polygons=Forests._development(source,layout,graph,field.to_ground); rules.include_polygons=[Forests._rectangle(rule.bounds,field.to_ground)]
		rules.water_depth_range=Vector2(0,.03)
		if rule.get("sidewalk",false) and str(rule.mode)=="Roadside": rules.exclude_polygons=Forests._development(source,layout,graph,field.to_ground,true); rules.anchor_height_mode=2
		rules.render_cluster_size=32.; rules.render_distance=minf(float(source.render_distance),300.) if source.render_distance>0. else 0.; rules.lod_enabled=true
		rules.stream_instances=true
		var polygon:=rules.include_polygons[0]; var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: bounds=bounds.expand(point)
		rules.region=bounds
		var mode:=str(rule.mode)
		if mode in ["Roadside","Grid","Anchors"]:
			rules.use_anchors=true
			var anchors:=_anchors(rule,graph,cancel)
			if anchors.get("cancelled",false): return {"cancelled":true}
			if not str(anchors.get("error","")).is_empty(): errors.append(anchors.error); continue
			rules.anchor_ids=anchors.ids
			for pose: Transform3D in anchors.poses: rules.anchor_points.append(field.to_ground*pose)
		elif mode=="Clusters": rules.cluster_count=clampi(ceili((rule.bounds as Rect2).get_area()/(float(rule.spacing)*float(rule.spacing)*8.)),1,512); rules.cluster_radius=float(rule.spacing)*2.
		var item:=Forests._component(source,"unused",str(rule.name),source.world_id); item.id=str(source.world_id)+":props:"+str(rule.id); item.parameters.world_key=item.id.trim_prefix(source.world_id); item.parameters.world_placement=rule.id; item.transform=field.to_world; item.parameters.world_pose=item.transform; item.parameters.world_scatter_defaults=Forests.baseline(rules); item.mesh=KiwiModelPrimitives.box(Vector3(bounds.size.x,.05,bounds.size.y))
		for vertex in item.mesh.vertices.size(): item.mesh.vertices[vertex]+=Vector3(bounds.get_center().x,0.,bounds.get_center().y)
		item.parameters.world_mesh_key=hash([item.mesh.vertices,item.mesh.faces]); document.components.append(item); settings[item.id]={"kind":"scatter","scatter":rules,"collision":rules.collisions}
	return {"settings":settings,"warnings":warnings,"errors":errors}
static func _anchors(rule: Dictionary,graph: Dictionary,cancel: Callable) -> Dictionary:
	var poses: Array[Transform3D]=[]; var ids:=PackedStringArray(); var spacing:=float(rule.spacing)
	if rule.mode=="Anchors":
		for index in rule.get("anchors",[]).size(): poses.append(rule.anchors[index]); ids.append(str(rule.id)+":"+str(index))
	elif rule.mode=="Grid":
		var bounds: Rect2=rule.bounds; var columns:=maxi(1,floori(bounds.size.x/spacing)); var rows:=maxi(1,floori(bounds.size.y/spacing)); var start:=bounds.get_center()-Vector2(columns-1,rows-1)*spacing*.5
		if columns*rows>20000: return {"error":"Grid placement exceeds 20,000 anchors. Increase spacing or shrink the region."}
		for z in rows:
			if cancel.is_valid() and cancel.call(): return {"cancelled":true}
			for x in columns: poses.append(Transform3D(Basis.IDENTITY,Vector3(start.x+x*spacing,0.,start.y+z*spacing))); ids.append(str(rule.id)+":grid:"+str(x)+":"+str(z))
	else:
		var roads: Dictionary={}
		for edge: Dictionary in graph.edges:
			if str(edge.get("mode","Ground"))!="Ground": continue
			if not rule.get("road_types",PackedStringArray()).is_empty() and not rule.road_types.has(str(edge.get("type","Residential Street"))): continue
			if rule.get("sidewalk",false) and (not edge.get("section",false) or float(edge.get("sidewalk",0.))<.6): continue
			var id:=str(edge.get("source_road_id",edge.id))
			if not roads.has(id): roads[id]={"points":PackedVector3Array(),"width":edge.width,"outer_half":preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(edge),"sidewalk_center":float(edge.width)*.5+float(edge.get("shoulder",0.))+float(edge.get("curb_width",.14))+float(edge.get("sidewalk",0.))*.5,"curb":float(edge.get("curb_height",0.))}
			var points: PackedVector3Array=roads[id].points
			for point: Vector3 in edge.points:
				if points.is_empty() or points[-1].distance_to(point)>.001: points.append(point)
			roads[id].points=points
		for id in roads:
			var points: PackedVector3Array=roads[id].points; var total:=0.; var next:=spacing*.5; var step:=0
			for segment in points.size()-1:
				if cancel.is_valid() and cancel.call(): return {"cancelled":true}
				var a:=points[segment]; var b:=points[segment+1]; var delta:=b-a; delta.y=0.; var length:=delta.length()
				if length<.001: continue
				var direction:=delta/length; var side:=Vector3(-direction.z,0.,direction.x)
				while next<total+length:
					var center:=a.lerp(b,(next-total)/length)
					for sign: float in [-1.,1.]:
						if (rule.get("sides","Both")=="Left" and sign>0.) or (rule.get("sides","Both")=="Right" and sign<0.): continue
						var position: Vector3=center+side*sign*(float(roads[id].sidewalk_center) if rule.get("sidewalk",false) else float(roads[id].outer_half)+maxf(.1,float(rule.get("setback",2.))))
						if rule.get("sidewalk",false): position.y+=float(roads[id].curb)+.015
						poses.append(Transform3D(Basis.looking_at(-side*sign,Vector3.UP),position)); ids.append(str(rule.id)+":"+str(id)+":"+str(step)+":"+str(sign))
						if poses.size()>20000: return {"error":"Roadside placement exceeds 20,000 anchors. Increase spacing or populate a smaller world."}
					step+=1; next+=spacing
				total+=length
	return {"poses":poses,"ids":ids,"error":""}
