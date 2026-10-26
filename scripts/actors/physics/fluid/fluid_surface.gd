class_name KiwiFluidSurface
extends RefCounted
## Sparse implicit surface, reconstructed with marching tetrahedra. The solver
## supplies world-space samples; no simulation particles are rendered as nodes.
const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETS := [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]
static func build(points: PackedVector3Array, foam: PackedFloat32Array, values: Dictionary) -> Dictionary:
	var started:=Time.get_ticks_usec(); var cell:=float(values.cell); var radius:=float(values.spacing)*1.65
	var field:={}; var gradients:={}; var froth:={}; var cells:={}; var error:=""
	for i in points.size():
		var low:=Vector3i((points[i]-Vector3.ONE*radius)/cell); var high:=Vector3i((points[i]+Vector3.ONE*radius)/cell)
		low-=Vector3i.ONE; high+=Vector3i.ONE
		for x in range(low.x,high.x+1):
			for y in range(low.y,high.y+1):
				for z in range(low.z,high.z+1):
					var key:=Vector3i(x,y,z); var delta:=Vector3(key)*cell-points[i]; var q:=1.0-delta.length_squared()/(radius*radius)
					if q<=0: continue
					var weight:=q*q*q
					field[key]=float(field.get(key,0))+weight
					gradients[key]=gradients.get(key,Vector3.ZERO)+delta*(6*q*q/(radius*radius))
					froth[key]=float(froth.get(key,0))+weight*(float(foam[i]) if i<foam.size() else 0.0)
		if field.size()>180000: error="Surface budget exceeded. Increase spacing or choose Fast quality."; break
	var mesh:=ArrayMesh.new()
	if not error.is_empty(): return {"mesh":mesh,"error":error,"microseconds":Time.get_ticks_usec()-started}
	var iso:=float(values.fluid_surface_level)
	for key: Vector3i in field:
		if float(field[key])<iso: continue
		for offset: Vector3i in CORNERS: cells[key-offset]=true
	var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var uv:=PackedVector2Array()
	for key: Vector3i in cells:
		var positions:=[]; var samples:=[]; var normal:=[]; var white:=[]
		for offset: Vector3i in CORNERS:
			var at:=key+offset; var density:=float(field.get(at,0))
			positions.append(Vector3(at)*cell); samples.append(density); normal.append(gradients.get(at,Vector3.ZERO)); white.append(float(froth.get(at,0))/maxf(.00001,density))
		for tet: Array in TETS:
			var inside:=[]; var outside:=[]
			for index: int in tet:
				if float(samples[index])>=iso: inside.append(index)
				else: outside.append(index)
			if inside.is_empty() or outside.is_empty(): continue
			var cuts:=[]
			for a: int in inside:
				for b: int in outside:
					var t:=clampf((iso-float(samples[a]))/(float(samples[b])-float(samples[a])),0,1)
					cuts.append([positions[a].lerp(positions[b],t),normal[a].lerp(normal[b],t).normalized(),lerpf(white[a],white[b],t)])
			var triangles: Array=[[0,1,2]] if cuts.size()==3 else [[0,1,2],[1,3,2]]
			for tri: Array in triangles:
				var cross: Vector3=(cuts[tri[1]][0]-cuts[tri[0]][0]).cross(cuts[tri[2]][0]-cuts[tri[0]][0])
				if cross.dot(cuts[tri[0]][1])>0: tri=[tri[0],tri[2],tri[1]]
				for index: int in tri:
					vertices.append(cuts[index][0]); normals.append(cuts[index][1]); colors.append(Color(cuts[index][2],0,0,1)); uv.append(Vector2(cuts[index][0].x,cuts[index][0].z))
	if not vertices.is_empty():
		var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_TEX_UV]=uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":mesh,"error":error,"microseconds":Time.get_ticks_usec()-started,"vertices":vertices.size(),"grid":field.size()}
