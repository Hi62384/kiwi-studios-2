class_name KiwiModelPrimitives
extends RefCounted
const SHAPES := ["Box","Sphere","Cylinder","Cone","Capsule","Plane","Torus","Prism","Gear","Pipe","Bolt","Arch","Stairs","Beam","Panel"]

static func defaults(kind: String) -> Dictionary:
	if preload("res://Workspaces/ModelWorkspace/natural_generator.gd").accepts(kind): return preload("res://Workspaces/ModelWorkspace/natural_generator.gd").defaults(kind)
	return {"size":Vector3(.25,.25,3) if kind=="Beam" else (Vector3(2,.1,2) if kind=="Panel" else Vector3.ONE),"radius":.5,"height":1.,"segments":24,"teeth":16,"tooth_depth":.12,"hole":.325 if kind=="Pipe" else 0.,"steps":6,"inner_ratio":.7}

static func create(kind: String, parameters: Dictionary = {}) -> KiwiModelMesh:
	if preload("res://Workspaces/ModelWorkspace/natural_generator.gd").accepts(kind): return preload("res://Workspaces/ModelWorkspace/natural_generator.gd").generate(kind,parameters).mesh
	var settings := defaults(kind); settings.merge(parameters,true); parameters=settings
	var dimensions: Vector3=parameters.get("size",Vector3.ONE)
	var radius: float=parameters.get("radius",.5); var height: float=parameters.get("height",1.)
	var segments: int=clampi(int(parameters.get("segments",24)),3,128)
	match kind:
		"Box","Beam","Panel": return box(dimensions)
		"Cylinder","Cone","Gear","Pipe","Bolt":
			var profile := PackedVector2Array()
			if kind=="Gear":
				var teeth := clampi(int(parameters.get("teeth",16)),4,64)
				for i in teeth*4:
					var angle := TAU*i/(teeth*4.); var r := radius + (float(parameters.get("tooth_depth",.12)) if i%4 in [1,2] else 0.)
					profile.append(Vector2(cos(angle),sin(angle))*r)
			else:
				if kind=="Bolt": segments=6
				for i in segments: profile.append(Vector2(cos(TAU*i/segments),sin(TAU*i/segments))*radius)
			if kind=="Bolt":
				var bolt := prism(profile,height*.2)
				for i in bolt.vertices.size(): bolt.vertices[i].y+=height*.4
				bolt.append_mesh(create("Cylinder",{"radius":radius*.45,"height":height*.85,"segments":24}),Transform3D(Basis.IDENTITY,Vector3(0,-height*.1,0)))
				return bolt
			return prism(profile,height,float(parameters.get("hole",0.)),0. if kind=="Cone" else 1.)
		"Arch":
			var profile := PackedVector2Array(); var inner := radius*float(parameters.get("inner_ratio",.7))
			for i in segments+1:
				var angle := PI*i/segments; profile.append(Vector2(cos(angle),sin(angle))*radius)
			for i in range(segments,-1,-1):
				var angle := PI*i/segments; profile.append(Vector2(cos(angle),sin(angle))*inner)
			var result := prism(profile,height)
			for i in result.vertices.size(): result.vertices[i]=Vector3(result.vertices[i].x,result.vertices[i].z,result.vertices[i].y)
			for f in result.faces.size(): result.faces[f].reverse(); result.uv[f].reverse()
			return result
		"Stairs":
			var result := KiwiModelMesh.new(); var count := clampi(int(parameters.get("steps",6)),1,64)
			for i in count:
				var step_size := Vector3(dimensions.x,dimensions.y*(i+1.)/count,dimensions.z/count)
				result.append_mesh(box(step_size),Transform3D(Basis.IDENTITY,Vector3(0,step_size.y*.5,dimensions.z*((i+.5)/count-.5))))
			return result
	var primitive: PrimitiveMesh
	match kind:
		"Sphere":
			var sphere := SphereMesh.new(); sphere.radius=radius; sphere.height=radius*2; sphere.radial_segments=segments; sphere.rings=maxi(4,segments/2); primitive=sphere
		"Capsule":
			var capsule := CapsuleMesh.new(); capsule.radius=radius; capsule.height=maxf(height,radius*2); capsule.radial_segments=segments; primitive=capsule
		"Plane":
			var plane := PlaneMesh.new(); plane.size=Vector2(dimensions.x,dimensions.z); primitive=plane
		"Torus":
			var torus := TorusMesh.new(); torus.inner_radius=radius*.65; torus.outer_radius=radius; torus.rings=segments; torus.ring_segments=12; primitive=torus
		"Prism":
			var prism_mesh := PrismMesh.new(); prism_mesh.size=dimensions; primitive=prism_mesh
	if primitive==null: return KiwiModelMesh.new()
	var mesh := KiwiModelMesh.from_mesh(primitive); mesh.smooth=kind in ["Sphere","Capsule","Torus"]
	return mesh

static func box(size: Vector3) -> KiwiModelMesh:
	var result := KiwiModelMesh.new()
	for i in 8: result.vertices.append((Vector3(i&1,(i>>1)&1,(i>>2)&1)-Vector3.ONE*.5)*size)
	for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
		result.add_face(PackedInt32Array(face),PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]))
	for f in result.faces.size():
		if result.normal(f).dot(result.center(f))<0: result.faces[f].reverse(); result.uv[f].reverse()
	return result

static func prism(profile: PackedVector2Array, height: float, hole: float=0., top_scale: float=1.) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); var count := profile.size()
	for level in 2:
		for p in profile: result.vertices.append(Vector3(p.x*(top_scale if level==1 else 1.),(level-.5)*height,p.y*(top_scale if level==1 else 1.)))
	if top_scale==0.:
		# One shared apex, not a ring of coincident vertices.
		result.vertices.resize(count); result.vertices.append(Vector3(0,height*.5,0))
	for i in count:
		var j := (i+1)%count
		result.add_face(PackedInt32Array([i,j,count]) if top_scale==0. else PackedInt32Array([i,j,j+count,i+count]))
	if hole>0. and top_scale>0.:
		var offset := result.vertices.size()
		for level in 2:
			for p in profile:
				var q := p.normalized()*minf(hole,p.length()*.95); result.vertices.append(Vector3(q.x,(level-.5)*height,q.y))
		for i in count:
			var j := (i+1)%count
			result.add_face(PackedInt32Array([offset+j,offset+i,offset+i+count,offset+j+count]))
			result.add_face(PackedInt32Array([i,offset+i,offset+j,j]))
			result.add_face(PackedInt32Array([i+count,j+count,offset+j+count,offset+i+count]))
	else:
		var bottom := PackedInt32Array(); var top := PackedInt32Array()
		for i in count: bottom.append(count-1-i); top.append(count+i)
		result.add_face(bottom)
		if top_scale>0.: result.add_face(top)
	# Determine each wall normal from its profile edge, not its distance from
	# the origin: offset profiles may lie entirely on one side of the origin.
	var area:=0.
	for i in count: area+=profile[i].cross(profile[(i+1)%count])
	for f in result.faces.size():
		var expected:=Vector3.ZERO
		if f<count:
			var edge:=profile[(f+1)%count]-profile[f]; expected=Vector3(edge.y,0.,-edge.x)*(1. if area>=0. else -1.)
		elif hole<=0.:
			expected=Vector3.DOWN if f==count else Vector3.UP
		if not expected.is_zero_approx() and result.normal(f).dot(expected)<0.: result.faces[f].reverse(); result.uv[f].reverse()
	return result
