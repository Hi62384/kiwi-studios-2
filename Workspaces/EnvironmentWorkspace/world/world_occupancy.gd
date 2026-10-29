extends RefCounted
## Capture on the main thread; workers receive polygons, never live scene objects.
static func capture(session: KiwiEnvironmentSession,id: String,source: Resource) -> String:
	source.occupied.clear()
	if not source.respect_existing_objects: return ""
	var document:=session.environment(); var world:=document.component(id)
	if world==null: return "The world no longer exists."
	var pose:=document.world_transform(world)
	if absf(pose.basis.determinant())<.000001: return "Restore a non-zero world scale before generating placement masks."
	var inverse:=pose.affine_inverse(); var buildings: Dictionary={}; var roots: Array[String]=[]
	var initial:=document.hierarchy_state()
	for item in document.components:
		if not item.parameters.has("architecture_source"): continue
		var owned: bool=str(item.parameters.get("world_owner",""))==id; var moved:=_moved(item,inverse*(initial.poses[item.id] as Transform3D))
		if owned and not moved: continue
		buildings[item.id]=item; roots.append(item.id)
	var hierarchy:=document.hierarchy_state(roots)
	for item in document.components:
		var polygon:=PackedVector2Array(); var local: Transform3D=inverse*hierarchy.poses[item.id]
		if buildings.has(item.id):
			var building: Resource=item.parameters.architecture_source
			for point: Vector2 in building.footprint:
				var transformed:=local*Vector3(point.x,0.,point.y); polygon.append(Vector2(transformed.x,transformed.z))
		else:
			var owned: bool=item.parameters.get("world_generated",false) and str(item.parameters.get("world_owner",""))==id; var moved:=_moved(item,local)
			if hierarchy.selected[item.id] or (owned and not moved) or item.parameters.get("editor_proxy",false): continue
			if document.component_kind(item.id)!="asset" or item.mesh==null or item.is_skeleton: continue
			var bounds:=item.mesh.bounds()
			for corner in 8:
				var transformed:=local*bounds.get_endpoint(corner); polygon.append(Vector2(transformed.x,transformed.z))
			polygon=Geometry2D.convex_hull(polygon)
			if polygon.size()>1 and polygon[0].is_equal_approx(polygon[-1]): polygon.remove_at(polygon.size()-1)
		if polygon.size()<3: continue
		var area:=0.
		for index in polygon.size(): area+=polygon[index].cross(polygon[(index+1)%polygon.size()])
		if absf(area)<.001: continue
		source.occupied.append({"owner":item.id,"polygon":polygon,"plot":str(item.parameters.get("world_plot","")),"world":str(item.parameters.get("world_owner",""))})
		if source.occupied.size()>16384: return "Existing-object footprints exceed the region budget. Generate a smaller environment region."
	return ""
static func _moved(item: KiwiModelComponent,pose: Transform3D) -> bool:
	if item.parameters.has("world_global_pose"): return not pose.is_equal_approx(item.parameters.world_global_pose)
	return item.transform!=item.parameters.get("world_pose",item.transform) or bool(item.parameters.get("world_manual_pose",false))
