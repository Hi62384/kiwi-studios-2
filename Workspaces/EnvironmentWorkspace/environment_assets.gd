class_name KiwiEnvironmentAssets
extends RefCounted
static var cache: Dictionary={}
static var revisions: Dictionary={}
static var material_cache: Dictionary={}
static var generation:=0
static func invalidate(path: String) -> void:
	generation+=1; revisions[path]=int(revisions.get(path,0))+1; var target:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
	if target!=path: revisions[target]=int(revisions.get(target,0))+1
	for source in cache.keys():
		if ProjectSettings.globalize_path(source).replace("\\","/").simplify_path()==target or cache[source].get("dependencies",[]).has(target):
			if source!=path: revisions[source]=int(revisions.get(source,0))+1
			cache.erase(source)
	material_cache.clear()
static func load_parts(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {"parts":[],"error":"Missing model: "+path,"key":0}
	if path.get_extension().to_lower() in ["tres","res"] and ResourceLoader.load(path) is KiwiEnvironmentDocument: return {"parts":[],"error":"Open this environment in Environment Creator or use it as a linked Scene environment asset.","key":0}
	var file:=FileAccess.open(path,FileAccess.READ); var key:=hash([path,FileAccess.get_modified_time(path),file.get_length() if file!=null else 0,revisions.get(path,0)])
	if cache.has(path) and cache[path].key==key: return cache[path]
	var source:=KiwiModelImport.load_document(path); var parts: Array=[]
	var linked: Dictionary=load("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").resolve(source)
	if linked.document!=null: source=linked.document
	parts=_model_parts(source)
	var result:={"parts":parts,"key":key,"dependencies":linked.get("dependencies",[]),"error":"" if not parts.is_empty() else "The source has no supported mesh surfaces: "+path}
	if cache.size()>=64: cache.erase(cache.keys()[0])
	cache[path]=result; return result
static func load_scatter_parts(value: Variant) -> Dictionary:
	if not value is KiwiModelDocument: return load_parts(str(value))
	if value is KiwiEnvironmentDocument: return {"parts":[],"key":0,"error":"Use a native Model resource for an embedded scatter palette."}
	var key:=content_stamp(value); var identity:="inline:"+str(value.get_instance_id())
	if cache.has(identity) and cache[identity].key==key: return cache[identity]
	var parts:=_model_parts(value); var result:={"parts":parts,"key":key,"error":"" if not parts.is_empty() else "The embedded model has no visible mesh geometry."}
	if cache.size()>=64: cache.erase(cache.keys()[0])
	cache[identity]=result; return result
static func _model_parts(source: KiwiModelDocument) -> Array:
	var parts: Array=[]
	for item in source.components:
		if item.mesh==null or not source.visible_component(item): continue
		var native_unchanged:=item.geometry_source!=null and item.modifiers.is_empty() and item.geometry_source_hash==hash([item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials]); var mesh: Mesh
		if native_unchanged:
			mesh=item.geometry_source.duplicate() as Mesh
			for surface in mini(mesh.get_surface_count(),item.surface_materials.size()): mesh.surface_set_material(surface,item.surface_materials[surface])
		else: mesh=item.render_mesh()
		if mesh!=null:
			for surface in mesh.get_surface_count():
				var authored:=mesh.surface_get_material(surface)
				if authored is ShaderMaterial: mesh.surface_set_material(surface,timeline_material(authored))
		if mesh!=null and mesh.get_surface_count()>0: parts.append({"mesh":mesh,"transform":source.world_transform(item),"name":item.title})
	return parts

static func material(value: Variant) -> Material:
	var key:=content_stamp(value)
	if material_cache.has(key): return material_cache[key]
	var result:=_material(value)
	if result is ShaderMaterial: result=timeline_material(result)
	if material_cache.size()>=64: material_cache.erase(material_cache.keys()[0])
	material_cache[key]=result; return result
static func _material(value: Variant) -> Material:
	var resource: Resource=value if value is Resource else null
	if value is String and str(value).get_extension().to_lower() in ["png","jpg","jpeg","webp","bmp","tga","exr","hdr"]:
		var image:=ActorImageGenerator.image_from_value(value)
		if image==null or image.is_empty(): return null
		var surface:=StandardMaterial3D.new(); surface.albedo_texture=ImageTexture.create_from_image(image); surface.uv1_triplanar=true; return surface
	if value is String and not str(value).is_empty() and ResourceLoader.exists(value): resource=ResourceLoader.load(value)
	if resource is ActorObjectReference: resource=ActorAnimation.resolve_reference(resource)
	if resource is ActorObjectData and resource.type_id in [&"image",&"noise_image"]:
		var result:=StandardMaterial3D.new(); result.albedo_texture=ActorImageGenerator.texture_for_object(resource); result.uv1_triplanar=true; return result
	if resource is Texture2D:
		var surface:=StandardMaterial3D.new(); surface.albedo_texture=resource; surface.uv1_triplanar=true; return surface
	return KiwiGrowthMaterial.from_asset(resource) if resource!=null else null

static func timeline_material(source: Material,force_copy: bool=false) -> Material:
	if not source is ShaderMaterial or source.shader==null: return source
	var existing: Variant=source.get_meta("kiwi_timeline_link") if source.has_meta("kiwi_timeline_link") else null
	if not force_copy and existing!=null and existing.has_method("active_for") and existing.active_for(source): return source
	if force_copy:
		var seen: Dictionary={}
		while existing!=null and existing.has_method("authoring_source") and not seen.has(source.get_instance_id()):
			seen[source.get_instance_id()]=true; var original: ShaderMaterial=existing.authoring_source()
			if original==null: break
			source=original; existing=source.get_meta("kiwi_timeline_link") if source.has_meta("kiwi_timeline_link") else null
	var result:=source.duplicate(false) as ShaderMaterial; var link:=preload("res://Workspaces/EnvironmentWorkspace/timeline_material_link.gd").new(); result.set_meta("kiwi_timeline_link",link); link.setup(source,result); return result

static func content_stamp(value: Variant,seen: Dictionary={},depth: int=0) -> int:
	if depth>8: return hash(value)
	if value is String and FileAccess.file_exists(value): return hash([value,FileAccess.get_modified_time(value),revisions.get(value,0)])
	if value is Array:
		var parts:=[]
		for entry in value: parts.append(content_stamp(entry,seen,depth+1))
		return hash(parts)
	if value is Dictionary:
		var parts:=[]
		for key in value: parts.append([key,content_stamp(value[key],seen,depth+1)])
		return hash(parts)
	if value is Resource:
		var id: int=value.get_instance_id()
		if seen.has(id): return hash(id)
		seen[id]=true
		var parts:=[id,content_stamp(value.resource_path,seen,depth+1)]
		if value is Image or (value is Texture2D and not (value is NoiseTexture2D or value is GradientTexture1D or value is GradientTexture2D)): return hash(parts)
		for property in value.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_STORAGE==0 or str(property.name) in ["script","resource_path","resource_name","resource_local_to_scene"]: continue
			parts.append([property.name,content_stamp(value.get(property.name),seen,depth+1)])
		return hash(parts)
	return hash(value)
static func world_stamp(document: KiwiEnvironmentDocument) -> int:
	var resolved: Resource=ActorAnimation.resolve_reference(document.atmosphere) if document.atmosphere!=null else null
	return hash([document.environment_id,content_stamp(document.environment_source),content_stamp(resolved),document.climate.signature() if document.climate!=null and document.climate.has_method("signature") else 0])

static func world_environment(document: KiwiEnvironmentDocument) -> Environment:
	var resource: Resource=ActorAnimation.resolve_reference(document.atmosphere) if document.atmosphere!=null else null
	if not document.environment_source.is_empty() and ResourceLoader.exists(document.environment_source): resource=ResourceLoader.load(document.environment_source,"",ResourceLoader.CACHE_MODE_REPLACE)
	if resource is Environment:
		if resource.sky!=null and resource.sky.sky_material is ShaderMaterial:
			var material:=timeline_material(resource.sky.sky_material)
			if material!=resource.sky.sky_material:
				var copy:=resource.duplicate(false) as Environment; copy.sky=resource.sky.duplicate(false); copy.sky.sky_material=material; return copy
		return resource
	if resource is ActorObjectData and resource.type_id==&"environment":
		var environment:=Environment.new(); var adapter: Node=load("res://scripts/actors/examples/basic_actor.gd").new(); adapter._configure_environment(environment,resource); adapter.free(); return environment
	return null
