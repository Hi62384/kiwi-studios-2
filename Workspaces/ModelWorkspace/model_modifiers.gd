class_name KiwiModelModifiers
extends RefCounted
const TYPES := ["Mirror","Linear array","Radial array","Subdivision","Smooth","Solidify","Twist","Taper","Bevel"]

static func evaluate(component: KiwiModelComponent) -> KiwiModelMesh:
	var mesh := component.mesh.copy_mesh() if component.mesh!=null else KiwiModelMesh.new()
	for settings in component.modifiers:
		if not settings.get("enabled",true): continue
		if mesh.vertices.size()>100000 or mesh.faces.size()>100000: break
		mesh=apply(mesh,settings)
	return mesh

static func apply(mesh: KiwiModelMesh, settings: Dictionary) -> KiwiModelMesh:
	var result := mesh.copy_mesh(); var axis := clampi(int(settings.get("axis",0)),0,2)
	var amount := float(settings.get("amount",1.)); var kind := str(settings.get("type",""))
	match kind:
		"Mirror":
			var half := mesh
			if settings.get("bisect",true):
				var direction := Vector3.ZERO; direction[axis]=-1. if mesh.bounds().get_center()[axis]>=0 else 1.
				half=KiwiModelGeometry.clip_plane(mesh,direction,0.)
				var cap := PackedInt32Array()
				for f in half.faces.size():
					var on_plane := true
					for index in half.faces[f]:
						if absf(half.vertices[index][axis])>.00001: on_plane=false; break
					if on_plane: cap.append(f)
				half=KiwiModelGeometry.remove_faces(half,cap)
			result=half.copy_mesh()
			var scale := Vector3.ONE; scale[axis]=-1
			result.append_mesh(half,Transform3D(Basis.from_scale(scale),Vector3.ZERO))
			result=KiwiModelGeometry.weld(result)
		"Linear array","Radial array":
			var count := clampi(int(settings.get("count",3)),1,64); var direction := Vector3.ZERO; direction[axis]=1
			if kind=="Radial array": result=KiwiModelMesh.new(); result.smooth=mesh.smooth
			for i in range(0 if kind=="Radial array" else 1,count):
				if result.vertices.size()+mesh.vertices.size()>150000: break
				var transform := Transform3D(Basis.IDENTITY,direction*amount*i)
				if kind=="Radial array":
					var basis := Basis(direction,TAU*i/count); var offset := Vector3.RIGHT if axis!=0 else Vector3.FORWARD
					transform=Transform3D(basis,basis*offset*amount)
				result.append_mesh(mesh,transform)
		"Subdivision":
			for unused in clampi(int(settings.get("count",1)),1,3):
				if result.faces.size()>20000: break
				result=KiwiModelGeometry.subdivide(result)
		"Smooth": result=KiwiModelGeometry.smooth_mesh(result,clampf(amount,0,1),clampi(int(settings.get("count",1)),1,8)); result.smooth=true
		"Solidify":
			var normals := PackedVector3Array(); normals.resize(mesh.vertices.size()); normals.fill(Vector3.ZERO)
			for f in mesh.faces.size():
				for index in mesh.faces[f]: normals[index]+=mesh.normal(f)
			var offset := mesh.vertices.size()
			for i in mesh.vertices.size(): result.vertices.append(mesh.vertices[i]-normals[i].normalized()*amount)
			for f in mesh.faces.size():
				var face := mesh.faces[f].duplicate(); var uv := mesh.uv[f].duplicate()
				for i in face.size(): face[i]+=offset
				face.reverse(); uv.reverse(); result.add_face(face,uv,mesh.materials[f])
			for edge in mesh.edges():
				if edge.faces.size()!=1: continue
				var face := mesh.faces[edge.faces[0]]; var a: int=edge.a; var b: int=edge.b
				if face[(face.find(a)+1)%face.size()]!=b: var temp:=a; a=b; b=temp
				result.add_face(PackedInt32Array([b,a,a+offset,b+offset]))
		"Twist","Taper":
			var box := mesh.bounds(); var extent := maxf(.001,box.size[axis]); var direction := Vector3.ZERO; direction[axis]=1
			for i in result.vertices.size():
				var p := result.vertices[i]; var t := (p[axis]-box.position[axis])/extent
				if kind=="Twist": p=Basis(direction,deg_to_rad(amount)*t)*p
				else:
					for j in 3:
						if j!=axis: p[j]*=maxf(.02,1.+amount*t)
				result.vertices[i]=p
		"Bevel":
			var bevel := KiwiModelGeometry.bevel(mesh,PackedInt32Array(),amount)
			if bevel!=null: result=bevel
	return result
