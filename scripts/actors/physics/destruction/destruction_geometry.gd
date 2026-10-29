class_name KiwiDestructionGeometry
extends RefCounted
## Immutable operation evaluation on Kiwi's existing editable polygon topology.
const TYPES := ["Plane fracture","Multi-piece fracture","Impact fracture","Crack","Bend","Tear","Carve sphere","Carve box","Carve cylinder","Dent","Twist","Stretch","Weakness region","Protected region","Impact impulse"]
const MAX_VERTICES:=20000
const MAX_PARTS:=48
static func closed(mesh: KiwiModelMesh) -> bool:
	if mesh.faces.is_empty() or not mesh.validate().is_empty(): return false
	for edge in mesh.edges():
		if edge.faces.size()!=2: return false
	return true
static func volume(mesh: KiwiModelMesh) -> float:
	var result:=0.0
	for f in mesh.faces.size():
		var indices:=mesh.triangles(f)
		for i in range(0,indices.size(),3):
			var a:=mesh.vertices[mesh.faces[f][indices[i]]]; var b:=mesh.vertices[mesh.faces[f][indices[i+1]]]; var c:=mesh.vertices[mesh.faces[f][indices[i+2]]]
			result+=a.dot(b.cross(c))/6.0
	return absf(result)
static func cut(mesh: KiwiModelMesh,normal: Vector3,distance: float,interior: int) -> KiwiModelMesh:
	var result:=KiwiModelGeometry.clip_plane(mesh,normal,distance)
	var degenerate:=PackedInt32Array()
	for f in result.faces.size():
		if result.normal(f).length_squared()<.5: degenerate.append(f)
	if not degenerate.is_empty(): result=KiwiModelGeometry.remove_faces(result,degenerate)
	for f in result.faces.size():
		var cap:=true
		for index in result.faces[f]:
			if absf(normal.dot(result.vertices[index])-distance)>.00003: cap=false; break
		if cap: result.materials[f]=interior
	return result
static func split(mesh: KiwiModelMesh,normal: Vector3,point: Vector3,interior: int) -> Array[KiwiModelMesh]:
	var result: Array[KiwiModelMesh]=[]; normal=normal.normalized()
	if normal.is_zero_approx(): normal=Vector3.RIGHT
	for sign in [1.,-1.]:
		var piece:=cut(mesh,normal*sign,point.dot(normal)*sign,interior)
		if piece.faces.size()>0 and piece.validate().is_empty(): result.append(piece)
	return result
static func subtract(mesh: KiwiModelMesh,cutter: KiwiModelMesh,interior: int) -> Array[KiwiModelMesh]:
	var result: Array[KiwiModelMesh]=[]; var inside:=mesh; var used:={}
	for f in cutter.faces.size():
		if inside.faces.is_empty(): break
		var n:=cutter.normal(f); var d:=n.dot(cutter.center(f)); var key:=str(n.snapped(Vector3.ONE*.0001))+str(snappedf(d,.0001))
		if used.has(key): continue
		used[key]=true
		var outside:=cut(inside,-n,-d,interior)
		if outside.faces.size()>0 and volume(outside)>.00000001: result.append(outside)
		inside=cut(inside,n,d,interior)
	return result
static func evaluate(source: KiwiModelMesh,operations: Dictionary,interior: int) -> Dictionary:
	var parts: Array[KiwiModelMesh]=[source.copy_mesh()]; var detached:=false
	# Preserve deliberately separate solid cells, rather than welding shared
	# corners and turning a doorway into an unsupported concave solid.
	var needs_solids:=false
	for operation: Dictionary in operations.values(): needs_solids=needs_solids or (operation.get("enabled",true) and int(operation.get("type",0)) in [0,1,2,3,6,7,8])
	if needs_solids and (not closed(source) or not KiwiModelGeometry.convex(source)): parts=_solid_islands(source)
	if parts.size()>MAX_PARTS: return {"error":"Source contains more than 48 solid sections. Split it into smaller actors before fracturing.","parts":[]}
	var expanded:={}
	for id: String in operations:
		var op: Dictionary=operations[id]; var path: PackedVector3Array=op.get("path",PackedVector3Array())
		if path.size()>1:
			if path.size()>33: return {"error":"Fracture paths support at most 32 segments.","parts":[]}
			for i in path.size()-1:
				var copy:=op.duplicate(); copy.erase("path"); copy.type=0; copy.position=(path[i]+path[i+1])*.5; copy.direction=(path[i+1]-path[i]).cross(op.get("direction",Vector3.FORWARD)).normalized(); expanded[id+":"+str(i)]=copy
		else: expanded[id]=op
	operations=expanded
	for id: String in operations:
		var op: Dictionary=operations[id]
		if not op.get("enabled",true) or int(op.get("type",0)) in KiwiDestructionAuthoring.NON_GEOMETRY: continue
		var kind:=clampi(int(op.get("type",0)),0,TYPES.size()-1); var next: Array[KiwiModelMesh]=[]
		var point: Vector3=op.get("position",Vector3.ZERO); var axis: Vector3=(op.get("direction",Vector3.RIGHT) as Vector3).normalized(); var radius:=maxf(.001,float(op.get("radius",.5))); var amount:=float(op.get("amount",1))
		if not point.is_finite() or not axis.is_finite() or not is_finite(amount): return {"error":"Damage parameters must be finite.","parts":[]}
		if axis.is_zero_approx(): axis=Vector3.RIGHT
		for part in parts:
			if op.get("region_enabled",false) and part.bounds().get_center().distance_to(op.get("region_center",Vector3.ZERO))>float(op.get("region_radius",.5))+part.bounds().size.length()*.5: next.append(part); continue
			if part.vertices.size()>MAX_VERTICES: return {"error":"Destruction supports at most 20,000 editable vertices per piece. Use a simpler source.","parts":[]}
			if kind in [0,1,2,3,6,7,8] and (not closed(part) or not KiwiModelGeometry.convex(part)):
				return {"error":"Solid fracture/carving currently requires closed convex components. Decompose the model into convex components first. The original mesh was preserved.","parts":[]}
			if kind in [0,1,2,5]:
				if kind==5 and closed(part): return {"error":"Tear currently supports thin/open sheets. Use plane fracture for a closed solid.","parts":[]}
				var pieces: Array[KiwiModelMesh]=[part]; var rng:=KiwiPowderSource.rng_for(int(op.get("seed",1)),id.hash())
				var count:=clampi(ceili(float(op.get("pieces",6))/maxi(1,parts.size())),1,16) if kind in [1,2] else 2
				for unused in count-1:
					var largest:=0; var size:=0.0
					for i in pieces.size():
						var candidate:=pieces[i].bounds().size.length_squared()
						if candidate>size: size=candidate; largest=i
					var p:=pieces[largest]; var normal:=axis if count==2 else Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
					if count>2:
						var grain: Vector3=(op.get("grain_direction",Vector3.UP) as Vector3).normalized(); var aligned:=grain.cross(normal).normalized()
						if aligned.is_zero_approx(): aligned=grain.cross(Vector3.RIGHT).normalized()
						normal=normal.lerp(aligned,clampf(float(op.get("anisotropy",0)),0,.98)).normalized()
						if float(op.get("branching",0))>.75: normal=normal.lerp(axis.cross(normal).normalized(),.4).normalized()
					var at:=point if count==2 else p.bounds().get_center()
					if count>2: at+=normal*rng.randf_range(-.15,.15)*p.bounds().size.length()*float(op.get("irregularity",0))
					if kind==2 and unused==0: at=p.bounds().get_center().lerp(point,.5)
					var protected:=false
					for region: Dictionary in op.get("protected_regions",[]):
						if absf(normal.dot(region.position-at))<float(region.radius): protected=true; break
					if protected: continue # Conservative: never cut through protected material.
					var divided:=split(p,normal,at,interior)
					if divided.size()==2: pieces.remove_at(largest); pieces.append_array(divided)
				for i in pieces.size():
					if kind==5:
						for v in pieces[i].vertices.size(): pieces[i].vertices[v]+=axis*(1 if i%2==0 else -1)*absf(amount)*.02
				next.append_array(pieces); detached=true
			elif kind in [3,6,7,8]:
				var cutter: KiwiModelMesh
				if kind==6: cutter=KiwiModelPrimitives.create("Sphere",{"radius":radius,"segments":8,"rings":4})
				elif kind==8: cutter=KiwiModelPrimitives.create("Cylinder",{"radius":radius,"height":maxf(.001,absf(amount)),"segments":10})
				else: cutter=KiwiModelPrimitives.box(Vector3(maxf(.002,radius*.06) if kind==3 else radius*2,maxf(.002,absf(amount)),radius*2))
				var rotation:=Quaternion(Vector3.UP,axis)
				for v in cutter.vertices.size(): cutter.vertices[v]=rotation*cutter.vertices[v]+point
				next.append_array(subtract(part,cutter,interior))
			else:
				var mesh:=part.copy_mesh()
				if kind in [4,9]:
					for unused in 2:
						if mesh.vertices.size()<2000: mesh=KiwiModelGeometry.subdivide(mesh)
				for i in mesh.vertices.size():
					var p:=mesh.vertices[i]-point; var t:=p.dot(axis)/radius; var radial:=p-axis*p.dot(axis)
					match kind:
						4:
							var side:=axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized(); var curvature:=amount/radius
							var maximum:=maxf(.001,mesh.bounds().size.length()*.5); curvature=clampf(curvature,-.85/maximum,.85/maximum)
							if absf(curvature)>.00001:
								var axial:=p.dot(axis); var across:=p.dot(side); p+=axis*((sin(curvature*axial)/curvature-across*sin(curvature*axial))-axial)+side*((1-cos(curvature*axial))/curvature+across*(cos(curvature*axial)-1))
						9: p+=axis*amount*pow(clampf(1-radial.length()/radius,0,1),maxf(.1,float(op.get("falloff",2))))
						10: p=Basis(axis,amount*t)*p
						11: p+=axis*p.dot(axis)*maxf(-.9,amount)*exp(-radial.length_squared()/(2*radius*radius))
					mesh.vertices[i]=p+point
				next.append(mesh)
		parts=next
		if parts.size()>MAX_PARTS: return {"error":"Damage exceeded the 48-piece safety limit; reduce cut or fracture detail.","parts":[]}
	for part in parts:
		if not part.validate().is_empty(): return {"error":"The operation produced degenerate geometry. Adjust its position or amount; original geometry was preserved.","parts":[]}
	return {"error":"","parts":parts,"detached":detached}
static func _solid_islands(source: KiwiModelMesh) -> Array[KiwiModelMesh]:
	var parents:=PackedInt32Array(); parents.resize(source.vertices.size())
	for index in parents.size(): parents[index]=index
	for face: PackedInt32Array in source.faces:
		if face.is_empty(): continue
		for index in range(1,face.size()):
			var a:=_island_root(parents,face[0]); var b:=_island_root(parents,face[index]); parents[b]=a
	var islands: Dictionary={}; var mappings: Dictionary={}
	for face in source.faces.size():
		var vertices: PackedInt32Array=source.faces[face]
		if vertices.is_empty(): continue
		var id:=_island_root(parents,vertices[0])
		if not islands.has(id): islands[id]=KiwiModelMesh.new(); mappings[id]={}
		var mesh: KiwiModelMesh=islands[id]; var mapping: Dictionary=mappings[id]; var indices:=PackedInt32Array()
		for vertex in vertices:
			if not mapping.has(vertex): mapping[vertex]=mesh.vertices.size(); mesh.vertices.append(source.vertices[vertex])
			indices.append(mapping[vertex])
		mesh.add_face(indices,source.uv[face],source.materials[face]); mesh.smooth=source.smooth
	var result: Array[KiwiModelMesh]=[]
	for mesh: KiwiModelMesh in islands.values(): result.append(mesh)
	return result
static func _island_root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index:
		parents[index]=parents[parents[index]]; index=parents[index]
	return index
