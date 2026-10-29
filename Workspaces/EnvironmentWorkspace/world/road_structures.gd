extends RefCounted
static func bridge(points: PackedVector3Array,width: float,pier_height: float=8.,ground: Callable=Callable(),sections: Dictionary={}) -> Dictionary:
	var geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd"); var deck:=KiwiModelModifiers.apply(geometry.strip(points,width,0.,sections),{"type":"Solidify","amount":.3}); var rail:=KiwiModelMesh.new(); var supports:=KiwiModelMesh.new(); var distance:=0.; var next_pier:=6.
	for sign: float in [-1.,1.]:
		var bar: KiwiModelMesh=geometry.strip(points,.12,sign*(width*.5-.12),sections)
		for index in bar.vertices.size(): bar.vertices[index].y+=1.06
		rail.append_mesh(KiwiModelModifiers.apply(bar,{"type":"Solidify","amount":.12}))
	for segment in points.size()-1:
		var a:=points[segment]; var b:=points[segment+1]; var length:=a.distance_to(b)
		if length<.001: continue
		var direction: Vector3=(b-a).normalized(); var side:=Vector3(-direction.z,0.,direction.x).normalized(); var basis:=Basis.looking_at(direction,Vector3.UP)
		while next_pier<=distance+length:
			var center:=a.lerp(b,(next_pier-distance)/length)
			for sign: float in [-1.,1.]:
				rail.append_mesh(KiwiModelPrimitives.box(Vector3(.12,1.,.12)),Transform3D(Basis.IDENTITY,center+side*sign*(width*.5-.12)+Vector3.UP*.5))
				var position:=center+side*sign*width*.3; var height:=maxf(.3,pier_height)
				if ground.is_valid():
					var surface: Dictionary=ground.call(Vector2(position.x,position.z))
					if surface.is_empty(): continue
					height=position.y-.3-float(surface.height)
					if height<.3: continue
				supports.append_mesh(KiwiModelPrimitives.box(Vector3(.6,height,.8)),Transform3D(basis,position-Vector3.UP*(height*.5+.3)))
			next_pier+=6.
		distance+=length
	return {"deck":deck,"railings":rail,"supports":supports}
static func portals(points: PackedVector3Array,width: float,start: bool=true,end: bool=true,frames: Array=[]) -> KiwiModelMesh:
	var result:=KiwiModelMesh.new(); var arch:=KiwiModelMesh.new(); var center:=(width*.65+2.)*.5; var radius:=sqrt(pow(width*.5+.35,2.)+center*center); var left:=PI+asin(center/radius); var right:=-asin(center/radius)
	for segment in 24:
		var a:=lerpf(left,right,float(segment)/24.); var b:=lerpf(left,right,float(segment+1)/24.); var profile:=PackedVector2Array()
		for entry: Vector2 in [Vector2(a,radius),Vector2(a,radius+.35),Vector2(b,radius+.35),Vector2(b,radius)]: profile.append(Vector2(cos(entry.x)*entry.y,maxf(0.,center+sin(entry.x)*entry.y)))
		var cell:=KiwiModelPrimitives.prism(profile,.45)
		for index in cell.vertices.size(): var p:=cell.vertices[index]; cell.vertices[index]=Vector3(p.x,p.z,p.y)
		for face in cell.faces.size(): cell.faces[face].reverse(); cell.uv[face].reverse()
		arch.append_mesh(cell)
	if not frames.is_empty():
		for frame: Dictionary in frames:
			var direction: Vector3=frame.direction; direction.y=0.; direction=direction.normalized(); result.append_mesh(arch,Transform3D(Basis.looking_at(direction,Vector3.UP),frame.position))
		return result
	for endpoint in [0,points.size()-1]:
		if endpoint==0 and not start or endpoint!=0 and not end: continue
		var direction: Vector3=(points[1]-points[0]).normalized() if endpoint==0 else (points[-2]-points[-1]).normalized(); direction.y=0.; direction=direction.normalized(); var pose:=Transform3D(Basis.looking_at(direction,Vector3.UP),points[endpoint]); result.append_mesh(arch,pose)
	return result
