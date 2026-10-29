extends ActorRuntime
var content: KiwiEnvironmentRuntime
var source_path:=""
var source_document: KiwiEnvironmentDocument
var error:=""
var linked_source_warning:=""
var shader_time:=0.
var climate_overrides: Dictionary={}
var _source_jobs: Array[Dictionary]=[]
var _source_generation:=0
func bind(data: ActorData) -> void:
	super.bind(data)
	if is_node_ready(): _load_source(str(data.get_value(&"environment_path","")))
func _ready() -> void:
	content=KiwiEnvironmentRuntime.new(); add_child(content); add_to_group("environment_asset_actors"); add_to_group("actor_shader_runtimes")
	preload("res://Workspaces/EnvironmentWorkspace/environment_world_override.gd").attach(self)
	if actor!=null and actor.get_value(&"environment_path","") is String: _load_source(str(actor.get_value(&"environment_path","")))
func physics_geometry_ready(need_physics: bool=true) -> bool: return content!=null and _source_jobs.is_empty() and content.geometry_ready(need_physics)
func physics_geometry_error() -> String:
	if not error.is_empty(): return error
	return content.building_stream.failure() if content!=null else "Environment runtime is unavailable."
func render_geometry_ready() -> bool: return content!=null and _source_jobs.is_empty() and content.geometry_ready(false)
func render_geometry_error() -> String: return physics_geometry_error()
func environment_for_physics() -> KiwiEnvironmentDocument: return source_document if _source_jobs.is_empty() and error.is_empty() else null
func environment_at(world_position: Vector3,time: float,overrides: Dictionary={}) -> Dictionary:
	if source_document==null or source_document.climate==null: return {}
	var local_position:=content.global_transform.affine_inverse()*world_position if content!=null else world_position
	return source_document.climate.call("evaluate",local_position,time,NAN,overrides if not overrides.is_empty() else climate_overrides)
func _process(_delta: float) -> void:
	var changed:=false
	for index in range(_source_jobs.size()-1,-1,-1):
		var entry: Dictionary=_source_jobs[index]; var job: RefCounted=entry.job
		if not job.complete(): continue
		job.collect(); _source_jobs.remove_at(index)
		if entry.generation!=_source_generation: continue
		if job.cancelled(): error="Environment preparation canceled."; continue
		if not str(job.error).is_empty(): error=str(job.error); continue
		source_document.component_settings[entry.id].terrain=job.terrain; source_document.component(entry.id).mesh=job.mesh; changed=true
	if _source_jobs.is_empty() and error=="Preparing environment terrain…":
		error=""; _configure_source()
	elif changed and _source_jobs.is_empty() and error.is_empty(): _configure_source()
func _cancel_source_jobs() -> void:
	_source_generation+=1
	for entry in _source_jobs: entry.job.cancel(); entry.job.collect()
	_source_jobs.clear()
func _exit_tree() -> void: _cancel_source_jobs()
func evaluate_transform(values: Dictionary) -> void:
	position=values.get(&"position",Vector3.ZERO); rotation_degrees=values.get(&"rotation",Vector3.ZERO); scale=values.get(&"scale",Vector3.ONE)
func set_active(value: bool) -> void:
	active=value
	if content!=null: content.visible=value
func supports_remote_transform() -> bool: return true
func water_at(world_point: Vector3) -> Dictionary:
	if not active or source_document==null: return {}
	return source_document.water_at(world_point,global_transform)
func remote_transform() -> Transform3D: return global_transform
func apply_remote_transform(source: Transform3D,move: bool,rotate: bool,resize: bool) -> void:
	var next:=global_transform
	if move: next.origin=source.origin
	var orientation:=source.basis.orthonormalized() if rotate else next.basis.orthonormalized(); next.basis=orientation*Basis.from_scale(source.basis.get_scale() if resize else next.basis.get_scale()); global_transform=next
func evaluate(_time: float,values: Dictionary) -> void:
	climate_overrides={"climate_time":float(values.get(&"climate_time",-1.)),"climate_weather":int(values.get(&"climate_weather",0)),"climate_intensity":float(values.get(&"climate_intensity",-1.)),"climate_clouds":float(values.get(&"climate_clouds",-1.)),"climate_temperature_offset":float(values.get(&"climate_temperature_offset",0.)),"climate_wind_add":values.get(&"climate_wind_add",Vector3.ZERO)}
	var changed:=content.include_lighting!=bool(values.get(&"include_lighting",true)) or content.include_atmosphere!=bool(values.get(&"include_atmosphere",false)); content.include_lighting=bool(values.get(&"include_lighting",true)); content.include_atmosphere=bool(values.get(&"include_atmosphere",false))
	var path: String=values.get(&"environment_path","") if values.get(&"environment_path") is String else ""
	if path!=source_path or source_document==null: _load_source(path)
	elif changed: content.sync_lighting()
	content.visible=active
func _load_source(path: String) -> void:
	_cancel_source_jobs(); source_path=path; error=""; linked_source_warning=""; source_document=null
	if not path.is_empty() and ResourceLoader.exists(path): source_document=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REUSE) as KiwiEnvironmentDocument
	if source_document==null:
		error="Choose a saved Environment document."; _clear_source(); return
	var errors:=source_document.validate()
	if not errors.is_empty(): error=errors[0]; _clear_source(); return
	var resolved:=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").resolve(source_document)
	if resolved.document!=null: source_document=resolved.document as KiwiEnvironmentDocument
	else: linked_source_warning=resolved.error+" Saved instance geometry is retained."
	_prepare_source()
func _prepare_source() -> void:
	_cancel_source_jobs(); var pending: Array[String]=[]
	for item in source_document.components:
		var terrain:=source_document.terrain(item.id)
		if terrain!=null and (terrain.resolution>257 or not terrain.water_valid() or not terrain.biomes_valid() or not terrain.volumes_valid() or not terrain.cave_biomes_valid()): pending.append(item.id)
	if pending.is_empty(): _configure_source(); return
	source_document=source_document.snapshot() as KiwiEnvironmentDocument; _clear_source(); error="Preparing environment terrain…"
	for id in pending:
		var job:=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd").new(); _source_jobs.append({"id":id,"generation":_source_generation,"job":job}); job.start(source_document.terrain(id),{},false)
func _configure_source() -> void:
	var chunks:=0
	for item in source_document.components:
		var terrain:=source_document.terrain(item.id)
		if terrain!=null: chunks+=ceili(float(terrain.resolution-1)/terrain.CHUNK_CELLS)*ceili(float(terrain.resolution-1)/terrain.CHUNK_CELLS)
	content.progressive=chunks>64 or source_document.components.size()>64; content.upload_budget_usec=8000; content.priority_camera=get_viewport().get_camera_3d(); content.configure(source_document); set_timeline_time(shader_time)
	if not linked_source_warning.is_empty(): content.errors.append(linked_source_warning)
func _clear_source() -> void:
	var empty:=KiwiEnvironmentDocument.new(); empty.sunlight={"enabled":false}; content.configure(empty)
func reload_environment(path: String) -> void:
	if ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()!=ProjectSettings.globalize_path(source_path).replace("\\","/").simplify_path(): return
	source_document=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	if source_document!=null: source_document.take_over_path(path); _prepare_source()
func refresh_saved_model(path: String) -> void:
	if source_document==null: return
	KiwiEnvironmentAssets.invalidate(path)
	if source_document.references_asset(path):
		var linked:=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").resolve(source_document)
		if linked.document!=null: source_document=linked.document as KiwiEnvironmentDocument; linked_source_warning=""
		else: linked_source_warning=linked.error+" Saved instance geometry is retained."
		# A changed image/material may live inside a linked model dependency.
		for metadata: Dictionary in source_document.component_settings.values():
			var sources: Array[String]=[str(metadata.get("source",""))]; var scatter:=metadata.get("scatter") as KiwiEnvironmentScatter
			if scatter!=null:
				for entry in scatter.palette: sources.append(str(entry.get("source","")))
			for source in sources:
				if not source.is_empty() and KiwiEnvironmentDocument._references(source,ProjectSettings.globalize_path(path).replace("\\","/").simplify_path(),{}): KiwiEnvironmentAssets.invalidate(source)
		_configure_source()
func refresh_saved_image(source: Variant) -> void:
	var path: String=str(source) if source is String else (source.resource_path if source is Resource else "")
	if not path.is_empty(): refresh_saved_model(path)
func set_timeline_time(time: float) -> void:
	shader_time=time
	content.preview_time=time
	var visited:={}
	for visual: Node in content.find_children("*","GeometryInstance3D",true,false):
		var mesh: Mesh=visual.mesh if visual is MeshInstance3D else (visual.multimesh.mesh if visual is MultiMeshInstance3D and visual.multimesh!=null else null)
		var materials: Array[Material]=[]
		if visual.material_override!=null: materials.append(visual.material_override)
		if mesh!=null:
			for surface in mesh.get_surface_count():
				var material: Material=visual.get_active_material(surface) if visual is MeshInstance3D else mesh.surface_get_material(surface)
				if material!=null: materials.append(material)
		for material in materials:
			if not material is ShaderMaterial or visited.has(material.get_instance_id()): continue
			material.set_meta("kiwi_last_time",time)
			if material.has_meta("kiwi_timeline_link"): material.get_meta("kiwi_timeline_link").synchronize_parameters()
			visited[material.get_instance_id()]=true; var uniform:=str(material.get_meta("kiwi_time_uniform",""))
			if not uniform.is_empty(): material.set_shader_parameter(uniform,time)
