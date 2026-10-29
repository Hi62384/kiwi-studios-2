extends RefCounted
static func controls(source: Resource) -> void:
	if source.terrain_field==null: return
	var fixed: Dictionary={}
	for road: Dictionary in source.roads:
		if str(road.get("mode","Ground"))!="Ground" or not road.get("follow_terrain",false): fixed[road.from]=true; fixed[road.to]=true
	for road: Dictionary in source.roads:
		if str(road.get("mode","Ground"))!="Ground" or not road.get("follow_terrain",false): continue
		var points: PackedVector3Array=road.points
		for index in points.size():
			if (index==0 and fixed.has(road.from)) or (index==points.size()-1 and fixed.has(road.to)): continue
			var surface: Dictionary=source.terrain_field.sample(Vector2(points[index].x,points[index].z))
			if not surface.is_empty(): points[index].y=float(surface.height)+.03
		road.points=points; source.nodes[road.from]=points[0]; source.nodes[road.to]=points[-1]
