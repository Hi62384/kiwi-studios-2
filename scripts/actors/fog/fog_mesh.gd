extends RefCounted
## Rigid, closed-mesh occupancy. Geometry is normalized to Volume Size, not
## rendered as a transparent shell. Topology is checked by the shared sampler.
static var cache: Dictionary={}
static var revisions: Dictionary={}
static var stamps: Dictionary={}
static func prepare(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path): return {"error":"Choose a saved closed Mesh resource."}
	var file:=FileAccess.open(path,FileAccess.READ); var stamp:=Vector2i(FileAccess.get_modified_time(path),file.get_length() if file!=null else 0); var reload: bool=stamps.has(path) and stamps[path]!=stamp; stamps[path]=stamp
	var mesh:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE if reload else ResourceLoader.CACHE_MODE_REUSE) as Mesh
	if mesh==null: return {"error":"The boundary must be a Mesh resource."}
	if reload: mesh.take_over_path(path)
	var identity:=mesh.get_instance_id()
	if not revisions.has(identity):
		revisions[identity]=0
		mesh.changed.connect(func(): revisions[identity]=int(revisions.get(identity,0))+1)
	var key:=str([path,stamp,identity,revisions[identity]].hash())
	if cache.has(key): return cache[key]
	var surfaces: Array=[]
	var triangles:=0
	for index in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES: return {"error":"Boundary surfaces must contain triangles."}
		var arrays:=mesh.surface_get_arrays(index); surfaces.append(arrays); var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array(); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; triangles+=(indices.size() if not indices.is_empty() else vertices.size())/3
		if triangles>10000: return {"error":"Fog boundaries support at most 10,000 triangles. Use a simplified closed mesh."}
	var checked:=KiwiVolumeSampler.closed_mesh({"meshes":[{"local":Transform3D.IDENTITY,"surfaces":surfaces}]})
	if not str(checked.error).is_empty():
		cache[key]=checked; return checked
	var bounds: AABB=checked.bounds
	if bounds.size.x<=.00001 or bounds.size.y<=.00001 or bounds.size.z<=.00001: return {"error":"The boundary must enclose a three-dimensional interior."}
	var size:=32; var slices: Array[Image]=[]; var start:=Time.get_ticks_usec()
	for z in size:
		var data:=PackedByteArray(); data.resize(size*size)
		for y in size:
			for x in size:
				var point:=bounds.position+(Vector3(x,y,z)+Vector3.ONE*.5)/size*bounds.size
				data[y*size+x]=255 if KiwiVolumeSampler.inside(checked.mesh,point,bounds.size.length()*3.) else 0
		var image:=Image.create_from_data(size,size,false,Image.FORMAT_R8,data); slices.append(image)
	var texture:=ImageTexture3D.new(); texture.create(Image.FORMAT_R8,size,size,size,false,slices)
	var result:={"error":"","texture":texture,"source":mesh,"slices":slices,"milliseconds":float(Time.get_ticks_usec()-start)/1000.}
	if cache.size()>=4: cache.erase(cache.keys()[0])
	key=str([path,stamp,identity,revisions[identity]].hash()); cache[key]=result; return result
