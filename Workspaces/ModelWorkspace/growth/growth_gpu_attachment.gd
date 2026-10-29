extends RefCounted
## Static strand vertices, dynamic source vertices and a bounded guide table.
## Each instance owns its pose textures/material, while the shader is shared.
var material: ShaderMaterial
var base_key: int=-1
var roots_key: int=0
var binding_key: int=0
var source_key: int=0
var motion_key: int=0
var textures: Dictionary={}
var guide_ids: Array=[]
var uploads:=0
var uploaded_bytes:=0
var bounds:=AABB()
var regional: Dictionary={}
var growth_extent:=.01
static func supports(data: KiwiSurfaceGrowthData) -> bool:
	if data.appearance==null or data.appearance.mode==2: return false
	for region: Dictionary in data.regions:
		if region.get("enabled",true) and region.get("material") is KiwiGrowthMaterial and int(region.material.mode)==2: return false
	return true
func upload(name: String,values: PackedFloat32Array) -> Texture2D:
	var pixels:=maxi(1,ceili(float(values.size())/4)); var width:=mini(256,pixels); var height:=ceili(float(pixels)/width); values.resize(width*height*4)
	var image:=Image.create_from_data(width,height,false,Image.FORMAT_RGBAF,values.to_byte_array()); var texture: ImageTexture=textures.get(name)
	if texture==null or texture.get_width()!=width or texture.get_height()!=height: texture=ImageTexture.create_from_image(image); textures[name]=texture
	else: texture.update(image)
	uploads+=1; uploaded_bytes+=width*height*16
	material.set_shader_parameter(name,texture); return texture
func point_table(points: PackedVector3Array) -> PackedFloat32Array:
	var result:=PackedFloat32Array(); result.resize(points.size()*4)
	for i in points.size(): result[i*4]=points[i].x; result[i*4+1]=points[i].y; result[i*4+2]=points[i].z
	return result
func update(instance: Variant,posed: PackedVector3Array,skinned: bool) -> void:
	var data: KiwiSurfaceGrowthData=instance.data; var base:=data.appearance.material() as ShaderMaterial
	if material==null: material=ShaderMaterial.new(); material.shader=base.shader
	if material.shader!=base.shader: material.shader=base.shader; base_key=-1
	if base_key!=data.appearance.runtime_key:
		for property: Dictionary in base.shader.get_shader_uniform_list(): material.set_shader_parameter(property.name,base.get_shader_parameter(property.name))
		base_key=data.appearance.runtime_key
		for name: String in textures: material.set_shader_parameter(name,textures[name])
	var next_roots:=hash([data.generation_key,data.source_points,data.revision,data.growth_style.values if data.growth_style!=null else {}])
	if roots_key!=next_roots:
		roots_key=next_roots; var triangles:=PackedFloat32Array(); triangles.resize(data.roots.size()*4)
		growth_extent=.01
		for i in data.roots.size():
			var root: Dictionary=data.roots[i]; var style:=KiwiSurfaceGrowth.style(data,root); var settings:=KiwiSurfaceGrowth.root_settings(data,root); triangles[i*4]=root.triangle.x; triangles[i*4+1]=root.triangle.y; triangles[i*4+2]=root.triangle.z; triangles[i*4+3]=maxf(.001,float(style.length)); growth_extent=maxf(growth_extent,maxf(float(style.length)*2.,float(settings.get("width",.14))*2.))
		upload("growth_triangles",triangles); upload("growth_rest_points",point_table(data.source_points)); source_key=0
	var next_source:=hash(posed)
	if source_key!=next_source:
		source_key=next_source; upload("growth_posed_points",point_table(posed))
		bounds=AABB(posed[0],Vector3.ZERO) if not posed.is_empty() else AABB()
		for point: Vector3 in posed: bounds=bounds.expand(point)
	if binding_key!=data.motion_binding or (guide_ids.is_empty() and not data.motion_guides.is_empty()):
		binding_key=data.motion_binding; guide_ids=data.motion_guides.keys(); guide_ids.sort(); var indices:=PackedFloat32Array(); var weights:=PackedFloat32Array(); indices.resize(data.roots.size()*4); indices.fill(-1.); weights.resize(indices.size())
		for i in data.roots.size():
			var links: Dictionary=data.motion_weights.get(str(data.roots[i].id),{}); var at:=0; var total:=0.
			for id: String in links:
				if at>=4: break
				var guide:=guide_ids.find(id)
				if guide<0: continue
				indices[i*4+at]=guide; weights[i*4+at]=maxf(0,float(links[id])); total+=weights[i*4+at]; at+=1
			for k in 4: weights[i*4+k]/=maxf(.00001,total)
		upload("growth_guide_indices",indices); upload("growth_guide_weights",weights); motion_key=0
	var next_motion:=hash(data.motion_guides)
	if not guide_ids.is_empty() and next_motion!=motion_key:
		motion_key=next_motion; var points:=PackedVector3Array()
		for id: String in guide_ids:
			var deltas: PackedVector3Array=data.motion_guides.get(id,{}).get("delta_points",PackedVector3Array([Vector3.ZERO,Vector3.ZERO])); points.append_array(deltas if deltas.size()==9 else KiwiSurfaceGrowth.resample_curve(deltas,9))
		upload("growth_guide_points",point_table(points))
	material.set_shader_parameter("growth_skin_attachment",skinned); material.set_shader_parameter("growth_guide_motion",not guide_ids.is_empty() and not data.motion_guides.is_empty()); material.set_shader_parameter("growth_motion_influence",data.motion_influence)
	material.set_shader_parameter("lod_density",data.lod_density); material.set_shader_parameter("coverage_scale",minf(4.,1./sqrt(data.lod_density)))
	var margin:=growth_extent
	for guide: Dictionary in data.motion_guides.values():
		for point: Vector3 in guide.get("delta_points",PackedVector3Array()): margin=maxf(margin,point.length()*2.)
	instance.custom_aabb=bounds.grow(margin)
	instance.material_override=material
func bind_regions(instance: Variant,deformed: bool=true) -> void:
	var data: KiwiSurfaceGrowthData=instance.data
	if data.regions.is_empty(): instance.material_override=material; return
	instance.material_override=null; var used:={}; var ready:={}
	for surface in instance.mesh.get_surface_count():
		var index:=int(data.surface_regions.get(surface,-1)); var appearance:=data.appearance
		if index>=0 and index<data.regions.size() and data.regions[index].get("material") is KiwiGrowthMaterial: appearance=data.regions[index].material
		if appearance.mode==2: instance.set_surface_override_material(surface,appearance.material()); continue
		var id:=appearance.get_instance_id(); used[id]=true
		if not regional.has(id): regional[id]={"material":ShaderMaterial.new(),"key":-1}
		var entry: Dictionary=regional[id]; var target:=entry.material as ShaderMaterial
		if not ready.has(id):
			ready[id]=true; var source:=appearance.material() as ShaderMaterial
			if target.shader!=source.shader: target.shader=source.shader; entry.key=-1
			if int(entry.key)!=appearance.runtime_key:
				for property: Dictionary in source.shader.get_shader_uniform_list(): target.set_shader_parameter(property.name,source.get_shader_parameter(property.name))
				entry.key=appearance.runtime_key
			if deformed:
				for name: String in textures: target.set_shader_parameter(name,textures[name])
				for name: String in ["growth_skin_attachment","growth_guide_motion","growth_motion_influence","lod_density","coverage_scale"]: target.set_shader_parameter(name,material.get_shader_parameter(name))
			else:
				target.set_shader_parameter("growth_skin_attachment",false); target.set_shader_parameter("growth_guide_motion",false); target.set_shader_parameter("lod_density",data.lod_density); target.set_shader_parameter("coverage_scale",minf(4.,1./sqrt(data.lod_density)))
		instance.set_surface_override_material(surface,target)
	for id: int in regional.keys():
		if not used.has(id): regional.erase(id)
