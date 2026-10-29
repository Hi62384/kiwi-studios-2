class_name KiwiSurfaceGrowthInstance
extends MeshInstance3D
var data: KiwiSurfaceGrowthData
var growth_skeleton: Skeleton3D
var pose_signature:=0
var gpu:=preload("res://Workspaces/ModelWorkspace/growth/growth_gpu_attachment.gd").new()
var gpu_bones_key:=0
var gpu_points:=PackedVector3Array()
var appearance_instance: ShaderMaterial
var appearance_key: int=-1
var appearance_source: Resource
func base_override() -> Material:
	var source:=data.appearance.material()
	if not source is ShaderMaterial: return source
	if appearance_instance==null: appearance_instance=ShaderMaterial.new()
	if appearance_instance.shader!=source.shader: appearance_instance.shader=source.shader; appearance_key=-1
	if appearance_source!=data.appearance or appearance_key!=data.appearance.runtime_key:
		for property: Dictionary in source.shader.get_shader_uniform_list(): appearance_instance.set_shader_parameter(property.name,source.get_shader_parameter(property.name))
		appearance_instance.set_meta("kiwi_time_uniform",source.get_meta("kiwi_time_uniform",""))
		appearance_source=data.appearance; appearance_key=data.appearance.runtime_key
	return appearance_instance
func set_growth_time(time: float) -> void:
	var materials: Array[Material]=[]
	if material_override!=null: materials.append(material_override)
	elif mesh!=null:
		for surface in mesh.get_surface_count(): materials.append(get_surface_override_material(surface) if get_surface_override_material(surface)!=null else mesh.surface_get_material(surface))
	for material: Material in materials:
		if material is ShaderMaterial:
			var uniform:=str(material.get_meta("kiwi_time_uniform",""))
			if not uniform.is_empty(): material.set_shader_parameter(uniform,time)
func configure(component: KiwiModelComponent,independent: bool=false) -> void:
	data=component.growth.copy_data() if independent else component.growth; mesh=KiwiSurfaceGrowth.render(data); layers=1
func update_growth() -> void:
	if data==null: return
	if data.appearance!=null: material_override=base_override() if data.regions.is_empty() else null
	update_lod()
	var skeleton:=growth_skeleton if is_instance_valid(growth_skeleton) else null
	var skinning:=skeleton!=null and data.source_skin!=null and not data.source_weights.is_empty() and data.rigid_bone<0
	var use_gpu:=DisplayServer.get_name()!="headless" and data.roots.size()>=int(data.rendering.get("gpu_threshold",3000)) and gpu.supports(data) and (skinning or not data.motion_guides.is_empty())
	if data.gpu_motion and not use_gpu and mesh!=null:
		for surface in mesh.get_surface_count(): set_surface_override_material(surface,null)
	data.gpu_motion=use_gpu
	if use_gpu:
		if skeleton!=null:
			if data.rigid_bone>=0 and data.rigid_bone<skeleton.get_bone_count(): global_transform=skeleton.global_transform*skeleton.get_bone_global_pose(data.rigid_bone)*data.rigid_offset
			else: global_transform=skeleton.global_transform
		if skinning:
			skeleton.force_update_all_bone_transforms(); var poses:=[]
			for i in skeleton.get_bone_count(): poses.append(skeleton.get_bone_global_pose(i))
			var key:=hash([poses,data.source_points])
			if key!=gpu_bones_key or gpu_points.is_empty(): gpu_bones_key=key; gpu_points=KiwiSurfaceGrowth.posed_points(data,skeleton)
		else: gpu_points=data.source_points
		gpu.update(self,gpu_points,skinning); mesh=KiwiSurfaceGrowth.render(data); gpu.bind_regions(self); return
	custom_aabb=AABB()
	if not is_instance_valid(growth_skeleton):
		mesh=KiwiSurfaceGrowth.render(data)
		if not data.regions.is_empty(): gpu.bind_regions(self,false)
		return
	if data.rigid_bone>=0 and data.rigid_bone<growth_skeleton.get_bone_count():
		global_transform=growth_skeleton.global_transform*growth_skeleton.get_bone_global_pose(data.rigid_bone)*data.rigid_offset; mesh=KiwiSurfaceGrowth.render(data)
		if not data.regions.is_empty(): gpu.bind_regions(self,false)
		return
	growth_skeleton.force_update_all_bone_transforms(); var poses:=[]
	for i in growth_skeleton.get_bone_count(): poses.append(growth_skeleton.get_bone_global_pose(i))
	var key:=hash([poses,data.revision,data.settings,data.groom_enabled,data.motion_guides,data.lod_upper,data.lod_detail,data.render_final])
	global_transform=growth_skeleton.global_transform
	if key==pose_signature:
		if not data.regions.is_empty(): gpu.bind_regions(self,false)
		return
	pose_signature=key; mesh=KiwiSurfaceGrowth.render(data,KiwiSurfaceGrowth.posed_points(data,growth_skeleton))
	if not data.regions.is_empty(): gpu.bind_regions(self,false)
func _process(_delta: float) -> void: update_growth()
func update_lod() -> void:
	var density:=1.; var detail:=0
	data.render_final=is_inside_tree() and get_viewport().get_meta("kiwi_final_growth",false)
	if is_inside_tree() and data.rendering.get("automatic_lod",true) and data.appearance!=null and data.appearance.mode!=2 and not get_viewport().get_meta("kiwi_final_growth",false):
		var camera:=get_viewport().get_camera_3d()
		if camera!=null:
			var near:=maxf(.1,float(data.rendering.get("near",4.))); var far:=maxf(near+.1,float(data.rendering.get("far",16.))); var distance:=camera.global_position.distance_to(global_position)
			var progress:=smoothstep(near,far,distance); density=lerpf(1.,clampf(float(data.rendering.get("minimum_density",.15)),.05,1.),progress); detail=0 if progress<.3 else (1 if progress<.8 else 2)
	if data.appearance!=null and data.appearance.mode==1: density*=.55
	data.lod_density=density; data.lod_upper=minf(1.,ceil((density+.05)*4.)/4.); data.lod_detail=detail
	if material_override is ShaderMaterial and data.appearance!=null and data.appearance.mode!=2:
		material_override.set_shader_parameter("lod_density",density); material_override.set_shader_parameter("coverage_scale",minf(4.,1./sqrt(density)))
	if not data.regions.is_empty():
		for region: int in range(-1,data.regions.size()):
			var material:=KiwiSurfaceGrowth.region_material(data,region)
			if data.appearance.mode!=2 and material is ShaderMaterial and material.shader==data.appearance.runtime.shader: material.set_shader_parameter("lod_density",density); material.set_shader_parameter("coverage_scale",minf(4.,1./sqrt(density)))
