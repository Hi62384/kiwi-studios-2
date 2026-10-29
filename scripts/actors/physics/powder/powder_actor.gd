class_name KiwiPowderRuntime
extends "res://scripts/actors/examples/basic_actor.gd"
var grains: MultiMeshInstance3D
var grain_material: ShaderMaterial
var batches: Array[MultiMeshInstance3D]=[]
var preview_key: int=-1
var preview_updates:=0
var visual_values: Dictionary={}
var geometry: Array[Mesh]=[]
var material_warning:=""
var _appearance_key: int=-1
var _identity_key: int=-1
var identities: Dictionary={}
func _ready() -> void:
	content=Node3D.new(); super._ready()
	grain_material=ShaderMaterial.new(); grain_material.shader=preload("res://scripts/actors/physics/powder/powder.gdshader")
	_add_batch(); grains=batches[0]
func _add_batch() -> void:
	var node:=MultiMeshInstance3D.new(); node.name="Grains"+str(batches.size()); content.add_child(node); node.set_as_top_level(true); node.global_transform=Transform3D.IDENTITY; node.layers=1
	node.multimesh=MultiMesh.new(); node.multimesh.transform_format=MultiMesh.TRANSFORM_3D; node.multimesh.use_custom_data=true; node.material_override=grain_material; batches.append(node)
func evaluate(time: float,values: Dictionary) -> void:
	super.evaluate(time,values)
	visual_values=KiwiPowderMaterial.appearance(values)
	var next:=KiwiPowderGeometry.variants(visual_values)
	if next!=geometry:
		geometry=next; preview_key=-1
		while batches.size()<geometry.size(): _add_batch()
		for i in batches.size():
			batches[i].multimesh.mesh=geometry[i] if i<geometry.size() else geometry[0]
			if i>=geometry.size(): batches[i].multimesh.instance_count=0
	var appearance_key:=hash(visual_values)
	if _appearance_key!=appearance_key:
		_appearance_key=appearance_key
		for pair in [["base_color","powder_color"],["secondary_color","powder_secondary"],["variation","powder_color_variation"],["roughness","powder_roughness"],["roughness_variation","powder_roughness_variation"],["metallic","powder_metallic"],["specular","powder_specular"],["opacity","powder_opacity"],["texture_scale","powder_texture_scale"],["texture_offset","powder_texture_offset"],["texture_blend","powder_texture_blend"],["texture_tint","powder_texture_tint"],["detail_intensity","powder_detail_intensity"],["normal_strength","powder_normal_strength"]]:
			if visual_values.has(StringName(pair[1])): grain_material.set_shader_parameter(pair[0],visual_values[StringName(pair[1])])
		grain_material.set_shader_parameter("texture_rotation",deg_to_rad(float(visual_values.get(&"powder_texture_rotation",0))))
		grain_material.set_shader_parameter("flat_shading",int(visual_values.get(&"powder_style",0))==1)
	for pair in [["powder_texture","albedo_map","has_albedo"],["powder_normal","normal_map","has_normal"],["powder_roughness_texture","roughness_map","has_roughness"]]:
		var texture:=_texture_for_value(visual_values.get(StringName(pair[0]))); grain_material.set_shader_parameter(pair[1],texture); grain_material.set_shader_parameter(pair[2],texture!=null)
	material_warning=""
	var ref: Variant=visual_values.get(&"powder_surface_material")
	var object:=ActorAnimation.resolve_reference(ref) if ref is ActorObjectReference else null
	if object!=null:
		if object.type_id==&"shader_material":
			var source: Variant=object.get_value(&"shader_path",""); var shader: Shader=source if source is Shader else (load(source) if source is String and ResourceLoader.exists(source) else null)
			if shader==null or shader.get_mode()!=Shader.MODE_SPATIAL: material_warning="Powder needs a spatial shader. Showing its built-in grain material instead."
		if material_warning.is_empty(): _apply_material_reference(ref,null,false)
	if object==null or not material_warning.is_empty(): _assign_material_override(grain_material)
	set_timeline_time(time)
	if not values.get(&"powder_enabled",true) or not values.get(&"physics",{}).get("enabled",true): clear_grains()
func _assign_material_override(value: Material) -> void:
	for batch in batches: batch.material_override=value
func clear_grains() -> void:
	for batch in batches: batch.multimesh.instance_count=0
	preview_key=-1
func show_state(state: Dictionary) -> void:
	if geometry.is_empty(): evaluate(0,actor.values)
	var points: PackedVector3Array=state.points; var radii: PackedFloat32Array=state.powder_radii
	var ids: PackedInt32Array=state.get("powder_ids",PackedInt32Array())
	if ids.size()!=points.size():
		ids.resize(points.size())
		for i in ids.size(): ids[i]=i
	var seed:=int(visual_values.get(&"powder_visual_seed",17)); var rotation:=float(visual_values.get(&"powder_rotation_variation",1))
	var identity_key:=hash([seed,rotation,geometry.size()])
	if _identity_key!=identity_key: identities.clear(); _identity_key=identity_key; preview_key=-1
	var key:=hash([points,radii,ids,identity_key])
	if preview_key==key: return
	preview_key=key; preview_updates+=1
	var buckets: Array[Array]=[]
	for i in geometry.size(): buckets.append([])
	for i in points.size():
		var id:=int(ids[i])
		if not identities.has(id):
			var rng:=KiwiPowderSource.rng_for(seed,id); var variant:=rng.randi_range(0,geometry.size()-1)
			var basis:=Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())*TAU*rotation)
			identities[id]={"variant":variant,"basis":basis,"custom":Vector4(rng.randf(),rng.randf(),rng.randf(),1)}
		buckets[int(identities[id].variant)].append(i)
	var bounds:=AABB(points[0],Vector3.ZERO) if not points.is_empty() else AABB(); var maximum:=0.0
	for i in points.size():
		bounds=bounds.expand(points[i]); maximum=maxf(maximum,radii[i]*1.8)
	for v in geometry.size():
		var buffer:=PackedFloat32Array(); buffer.resize(buckets[v].size()*16)
		for j in buckets[v].size():
			var i: int=buckets[v][j]; var offset:=j*16; var identity: Dictionary=identities[int(ids[i])]
			var b: Basis=identity.basis.scaled(Vector3.ONE*radii[i]); var p:=points[i]; var data: Vector4=identity.custom
			buffer[offset]=b.x.x; buffer[offset+1]=b.y.x; buffer[offset+2]=b.z.x; buffer[offset+3]=p.x
			buffer[offset+4]=b.x.y; buffer[offset+5]=b.y.y; buffer[offset+6]=b.z.y; buffer[offset+7]=p.y
			buffer[offset+8]=b.x.z; buffer[offset+9]=b.y.z; buffer[offset+10]=b.z.z; buffer[offset+11]=p.z
			for c in 4: buffer[offset+12+c]=data[c]
		batches[v].multimesh.instance_count=buckets[v].size()
		if not buckets[v].is_empty(): batches[v].multimesh.buffer=buffer; batches[v].multimesh.custom_aabb=bounds.grow(maximum)
func instance_count() -> int:
	var count:=0
	for batch in batches: count+=batch.multimesh.instance_count
	return count
