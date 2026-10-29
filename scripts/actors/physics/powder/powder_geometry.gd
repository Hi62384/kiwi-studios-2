class_name KiwiPowderGeometry
extends RefCounted
## Small shared geometry bank, never one mesh or material per grain.
static var cache: Dictionary={}
static var builds:=0
static func variants(values: Dictionary) -> Array[Mesh]:
	var shape:=clampi(int(values.get(&"powder_grain_shape",1)),0,4)
	var detail:=clampi(int(values.get(&"powder_render_detail",1)),0,2)
	var variation:=clampf(float(values.get(&"powder_shape_variation",.25)),0,1)
	var seed:=int(values.get(&"powder_visual_seed",17))
	var custom: Array[Mesh]=[]
	if shape==4:
		for key in [&"powder_custom_mesh",&"powder_custom_mesh_2",&"powder_custom_mesh_3"]:
			var source: Variant=values.get(key)
			if source is Mesh: custom.append(source)
			elif source is String and not source.is_empty() and ResourceLoader.exists(source):
				var mesh:=ResourceLoader.load(source) as Mesh
				if mesh!=null: custom.append(mesh)
	var identities:=[]
	for mesh in custom: identities.append(KiwiPhysicsSettings.canonical(mesh))
	var key:=hash([shape,detail,variation,seed,values.get(&"powder_variants",3),identities])
	if cache.has(key): return cache[key]
	var result: Array[Mesh]=[]
	var count:=custom.size() if not custom.is_empty() else clampi(int(values.get(&"powder_variants",3)),1,8)
	for i in count:
		var mesh: Mesh
		if not custom.is_empty(): mesh=normalized(custom[i])
		elif shape==0:
			var sphere:=SphereMesh.new(); sphere.radius=1; sphere.height=2; sphere.radial_segments=[6,10,16][detail]; sphere.rings=[3,5,8][detail]; mesh=sphere
		elif shape==3:
			var crystal:=CylinderMesh.new(); crystal.top_radius=.45; crystal.bottom_radius=.75; crystal.height=1.65; crystal.radial_segments=4 if i%2==0 else 6; crystal.rings=1; mesh=deform(crystal,variation,seed+i*733)
		else:
			var stone:=SphereMesh.new(); stone.radius=1; stone.height=2; stone.radial_segments=[5,7,10][detail]; stone.rings=[2,3,4][detail]
			mesh=deform(stone,variation*(1.0 if shape==2 else .5),seed+i*733)
		result.append(mesh)
	builds+=1
	if cache.size()>=32: cache.erase(cache.keys()[0])
	cache[key]=result
	return result

static func normalized(mesh: Mesh) -> Mesh:
	var result:=ArrayMesh.new(); var bounds:=mesh.get_aabb(); var extent:=maxf(.00001,bounds.size.length()*.5)
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays:=mesh.surface_get_arrays(surface).duplicate(true); var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in points.size(): points[i]=(points[i]-bounds.get_center())/extent
		arrays[Mesh.ARRAY_VERTEX]=points; result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func deform(mesh: Mesh,amount: float,seed: int) -> Mesh:
	var source:=mesh.surface_get_arrays(0); var points: PackedVector3Array=source[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=source[Mesh.ARRAY_INDEX]; var uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV]
	var rng:=KiwiPowderSource.rng_for(seed,47); var stretch:=Vector3(rng.randf_range(.75,1),rng.randf_range(.65,1),rng.randf_range(.7,1))
	for i in points.size():
		var p:=points[i]; var noise:=sin(p.x*9.7+p.y*13.1+p.z*7.3+seed)*sin(p.x*3.1-p.y*6.7+p.z*4.3+seed*.17)
		points[i]=p*stretch*(1+noise*amount*.27)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_smooth_group(-1)
	for i in indices.size():
		var index:=indices[i]; surface.set_uv(uv[index]); surface.add_vertex(points[index])
	surface.generate_normals(); surface.generate_tangents()
	return surface.commit()
