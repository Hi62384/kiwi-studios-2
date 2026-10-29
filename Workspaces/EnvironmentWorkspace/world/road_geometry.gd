extends RefCounted
## Continuous shared-vertex strips, cut back to explicit junction boundaries.
static func sample(points: PackedVector3Array,spacing: float=2.) -> PackedVector3Array:
	var result:=PackedVector3Array()
	if points.size()<2: return result
	for index in points.size()-1:
		var a:=points[maxi(0,index-1)]; var b:=points[index]; var c:=points[index+1]; var d:=points[mini(points.size()-1,index+2)]; var count:=clampi(ceili(b.distance_to(c)/maxf(.25,spacing)),1,128)
		for step in count:
			var t:=float(step)/count
			var point:=b.cubic_interpolate(c,a,d,t)
			if result.is_empty() or point.distance_squared_to(result[-1])>.000001: result.append(point)
	result.append(points[-1]); return result
static func trim(points: PackedVector3Array,start: float,end: float) -> PackedVector3Array:
	var result:=points.duplicate()
	for side in 2:
		if side==1: result.reverse()
		var distance:=start if side==0 else end
		while result.size()>2 and result[0].distance_to(result[1])<distance: distance-=result[0].distance_to(result[1]); result.remove_at(0)
		if result.size()>1: result[0]=result[0].move_toward(result[1],minf(distance,result[0].distance_to(result[1])*.8))
	if result.size()>1: result.reverse()
	return result
static func strip(points: PackedVector3Array,width: float,offset: float=0.,sections: Dictionary={}) -> KiwiModelMesh:
	var mesh:=KiwiModelMesh.new(); var distance:=0.
	if points.size()<2: return mesh
	for index in points.size():
		var before: Vector3=(points[index]-points[maxi(0,index-1)]).normalized(); var after: Vector3=(points[mini(points.size()-1,index+1)]-points[index]).normalized(); var direction: Vector3=(before+after).normalized(); direction.y=0.; direction=direction.normalized()
		if direction.is_zero_approx(): direction=Vector3.FORWARD
		var sideways:=Vector3(-direction.z,0.,direction.x); var tangent: Vector3=after if not after.is_zero_approx() else before; tangent.y=0.; tangent=tangent.normalized(); var edge_normal:=Vector3(-tangent.z,0.,tangent.x); var miter:=1./maxf(.5,absf(sideways.dot(edge_normal)))
		var override: Variant=sections.get("start") if index==0 else (sections.get("end") if index==points.size()-1 else null)
		if override is Vector3: sideways=override; miter=1.
		for side in [-.5,.5]: mesh.vertices.append(points[index]+sideways*(offset+width*side)*miter)
		if index==0: continue
		var previous_distance:=distance; distance+=points[index].distance_to(points[index-1]); var base: int=(index-1)*2; var face:=PackedInt32Array([base,base+2,base+3,base+1]); var uv:=PackedVector2Array([Vector2(0,previous_distance/width),Vector2(0,distance/width),Vector2(1,distance/width),Vector2(1,previous_distance/width)]); var f:=mesh.add_face(face,uv)
		if mesh.normal(f).y<0.: mesh.faces[f].reverse(); mesh.uv[f].reverse()
	return mesh
static func junction(center: Vector3,ends: Array) -> KiwiModelMesh:
	var profile:=PackedVector2Array(); var heights: Dictionary={}
	for end: Dictionary in ends:
		var point: Vector3=end.point; var direction: Vector3=end.direction; var side:=Vector3(-direction.z,0.,direction.x).normalized()*float(end.width)*.5
		for sign in [-1.,1.]:
			var coordinate:=Vector2(point.x+side.x*sign,point.z+side.z*sign); profile.append(coordinate); heights[coordinate]=point.y
	var mesh:=KiwiModelMesh.new()
	if profile.size()<3: return mesh
	profile=Geometry2D.convex_hull(profile)
	if profile.size()>1 and profile[0].is_equal_approx(profile[-1]): profile.remove_at(profile.size()-1)
	for point in profile: mesh.vertices.append(Vector3(point.x,float(heights.get(point,center.y)),point.y))
	var triangles:=Geometry2D.triangulate_polygon(profile)
	for index in range(0,triangles.size(),3):
		var f:=mesh.add_face(PackedInt32Array([triangles[index],triangles[index+1],triangles[index+2]]))
		if mesh.normal(f).y<0.: mesh.faces[f].reverse(); mesh.uv[f].reverse()
	return mesh
