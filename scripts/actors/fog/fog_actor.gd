extends RefCounted
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const SURFACE=preload("res://scripts/actors/fog/fog_surface.gdshader")

static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id!=&"fog_volume" or d.find_property(&"appearance")!=null: return
	d.find_property(&"shape").options.choices=["Ellipsoid","Cone","Cylinder","Box","World","Sphere","Capsule","Closed mesh"]
	var mesh:=ActorProperty.create(&"boundary_mesh","Closed boundary mesh",""); mesh.options.merge({"group":"Volume","file_picker":true,"extensions":["tres","res","mesh"],"native_resource_types":["Mesh"],"file_resource_mode":"uneditable","visible_when":{"property":"shape","values":[7]}}); d.properties.append(mesh)
	for row in [["appearance","Appearance","fog_appearance","Appearance"],["field","Density field","fog_field","Density"]]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],null); p.object_type=StringName(row[2]); p.options.group=row[3]; d.properties.append(p)
	var p:=ActorProperty.create(&"fog_presets","Appearance presets",0); p.options={"default":0,"group":"Appearance","fog_presets":true}; d.properties.append(p)

static func global_definition(local: ActorDefinition) -> ActorDefinition:
	var d:=local.duplicate(true) as ActorDefinition; d.type_id=&"global_fog"; d.display_name="Global Fog"; d.description="Scene-wide volumetric atmosphere. Lowest actor ID owns the global atmosphere when several overlap."
	d.icon=load("res://resources/Images/ActorIcons/GlobalFog.svg")
	d.find_property(&"shape").options.default=4; d.find_property(&"shape").options.hidden=true; d.find_property(&"volume_size").options.hidden=true
	d.find_property(&"density").options.default=.02
	# Global atmosphere is unbounded and cannot own a finite transport domain.
	d.properties=d.properties.filter(func(p: ActorProperty): return not str(p.id).begins_with("fog_") or p.id==&"fog_presets")
	preload("res://scripts/actors/fog/fog_motion_definition.gd").extend_actor(d)
	return d

static func apply(runtime: Node,values: Dictionary) -> void:
	var fog:=runtime.content as FogVolume; var is_global: bool=runtime.actor.type_id==&"global_fog" or int(values.get(&"shape",3))==4
	var kind:=int(values.get(&"shape",3)); fog.shape=RenderingServer.FOG_VOLUME_SHAPE_WORLD if is_global else (kind if kind<5 else RenderingServer.FOG_VOLUME_SHAPE_BOX)
	fog.size=(values.get(&"volume_size",Vector3(4,2,4)) as Vector3).abs().max(Vector3.ONE*.001)
	# Existing custom fog shaders remain authoritative and retain their uniforms.
	if values.get(&"material")!=null: return
	var appearance:=resolve(values.get(&"appearance")); var field:=resolve(values.get(&"field"))
	if appearance==null and field==null and kind<5 and not is_global and int(values.get(&"fog_motion_mode",0))==0: return
	var material: ShaderMaterial=fog.get_meta("kiwi_fog_material") if fog.has_meta("kiwi_fog_material") else null
	if material==null: material=ShaderMaterial.new(); material.shader=SURFACE; fog.set_meta("kiwi_fog_material",material)
	fog.material=material
	var v: Dictionary=appearance.values if appearance!=null else {}
	var cloud_lod: bool=bool(v.get(&"cloud_lod",false)) and field!=null and int(field.values.get(&"mode",0))==8
	material.set_shader_parameter("cloud_lod",cloud_lod); material.set_shader_parameter("cloud_detail_distance",maxf(1.,float(v.get(&"cloud_detail_distance",50.))))
	if cloud_lod:
		var low:=field.values.duplicate(); low[&"resolution"]=0; material.set_shader_parameter("cloud_low",Field.texture(low))
	for pair in [["render_style",0],["stylization",1.],["shading_bands",3],["shadow_tint",Color(.35,.42,.55)],["highlight",1.],["cloud_lighting",false],["cloud_shadow_strength",1.],["silver_lining",0.]]: material.set_shader_parameter(pair[0],v.get(StringName(pair[0]),pair[1]))
	for pair in [["density_multiplier","density_multiplier",1.],["contrast","contrast",1.],["density_offset","offset",0.],["threshold","threshold",0.],["maximum_density","maximum",64.],["opacity","opacity",1.],["scattering","scattering",1.],["absorption","absorption",0.],["secondary","secondary",Color.WHITE],["gradient_mode","gradient",0],["gradient_direction","direction",Vector3.UP],["world_mapping","world_space",false],["texture_scale","texture_scale",Vector3.ONE],["texture_offset","texture_offset",Vector3.ZERO],["texture_mapping","texture_mapping",0],["texture_strength","texture_strength",1.]]:
		material.set_shader_parameter(pair[0],v.get(StringName(pair[1]),pair[2]))
	material.set_shader_parameter("base_density",maxf(0.,float(values.get(&"density",1.))))
	material.set_shader_parameter("has_source_field",field!=null)
	if int(values.get(&"fog_motion_mode",0))<2: material.set_shader_parameter("has_simulation",false)
	material.set_shader_parameter("base_color",v.get(&"color",values.get(&"albedo",Color.WHITE)))
	material.set_shader_parameter("emission_color",v.get(&"emission",values.get(&"emission",Color.BLACK)))
	material.set_shader_parameter("emission_energy",v.get(&"emission_energy",values.get(&"emission_energy",1.)))
	material.set_shader_parameter("gradient_range",Vector3(float(v.get(&"gradient_start",0.)),float(v.get(&"gradient_end",1.)),float(v.get(&"gradient_falloff",1.))))
	material.set_shader_parameter("texture_contrast",maxf(.01,float(v.get(&"texture_contrast",1.)))); material.set_shader_parameter("texture_tiling",v.get(&"texture_tiling",true))
	material.set_shader_parameter("third_color",v.get(&"third_color",Color.WHITE)); material.set_shader_parameter("fourth_color",v.get(&"fourth_color",Color.WHITE)); material.set_shader_parameter("gradient_stops",clampi(int(v.get(&"gradient_stops",2)),2,4)); material.set_shader_parameter("gradient_positions",Vector2(float(v.get(&"stop_2",.33)),float(v.get(&"stop_3",.66))))
	material.set_shader_parameter("texture_rotation",Basis.from_euler((v.get(&"texture_rotation",Vector3.ZERO) as Vector3)*PI/180.))
	material.set_shader_parameter("world_to_local",fog.global_transform.affine_inverse() if absf(fog.global_transform.basis.determinant())>.000001 else Transform3D.IDENTITY)
	material.set_shader_parameter("volume_dimensions",fog.size)
	material.set_shader_parameter("shape_kind",kind); material.set_shader_parameter("edge_fade",maxf(.0001,float(values.get(&"edge_fade",.1)))); material.set_shader_parameter("global_volume",is_global)
	var boundary: Dictionary={}
	if kind==7: boundary=preload("res://scripts/actors/fog/fog_mesh.gd").prepare(str(values.get(&"boundary_mesh","")))
	material.set_shader_parameter("has_boundary",boundary.get("texture")!=null); material.set_shader_parameter("boundary_map",boundary.get("texture")); fog.set_meta("fog_boundary_error",boundary.get("error",""))
	for role in ["color","density","mask","detail"]:
		var image:=resolve(v.get(StringName(role+"_texture"))); var texture: Texture2D=runtime._texture_for_value(ActorObjectReference.from_object(image)) if image!=null else null
		material.set_shader_parameter(role+"_map",texture); material.set_shader_parameter("has_"+role,texture!=null)
	for role in ["density","color"]:
		var path:=str(v.get(StringName(role+"_volume"),"")); var texture: Texture3D=ResourceLoader.load(path) as Texture3D if not path.is_empty() and ResourceLoader.exists(path) else null
		material.set_shader_parameter(role+"_volume",texture); material.set_shader_parameter("has_"+role+"_volume",texture!=null)
	var layers: Array[ActorObjectData]=[]
	if field!=null: layers.append(field)
	for index in 4:
		var layer:=resolve(v.get(StringName("layer_%d"%index)))
		if layer!=null: layers.append(layer)
	# One spatial field plus four appearance influences share one fog pass.
	var modes:=PackedVector4Array(); var params:=PackedVector4Array(); var directions:=PackedVector4Array(); var scales:=PackedVector4Array(); var offsets:=PackedVector4Array(); var colors:=PackedVector4Array(); var thresholds:=PackedFloat32Array(); var uniform_values:=PackedFloat32Array(); var masks:=PackedFloat32Array()
	var shapes:=PackedVector4Array(); var rotations:=PackedVector4Array(); var edges:=PackedFloat32Array(); var cloud_ground:=PackedVector4Array()
	for index in 5:
		var f: Dictionary=layers[index].values if index<layers.size() else {}; var enabled:=index<layers.size() and bool(f.get(&"enabled",true))
		cloud_ground.append(Vector4(float(f.get(&"cloud_type",0)),float(f.get(&"cloud_ground_height",0.)),float(f.get(&"cloud_ground_falloff",2.)),0.))
		modes.append(Vector4(1. if enabled else 0.,float(f.get(&"mode",0)),float(f.get(&"combine",1)),float(f.get(&"target",0))))
		params.append(Vector4(float(f.get(&"strength",1.)),float(f.get(&"start",0.)),float(f.get(&"end",1.)),float(f.get(&"falloff",1.))))
		var dir: Vector3=f.get(&"direction",Vector3.UP); directions.append(Vector4(dir.x,dir.y,dir.z,1. if f.get(&"world_space",false) else 0.))
		var scale: Vector3=f.get(&"scale",Vector3.ONE); scales.append(Vector4(scale.x,scale.y,scale.z,1. if f.get(&"invert",false) else 0.))
		var offset: Vector3=f.get(&"offset",Vector3.ZERO); offsets.append(Vector4(offset.x,offset.y,offset.z,maxf(.01,float(f.get(&"contrast",1.)))))
		var color: Color=f.get(&"color",Color.WHITE); colors.append(Vector4(color.r,color.g,color.b,color.a)); thresholds.append(float(f.get(&"threshold",0.)))
		uniform_values.append(float(f.get(&"value",1.)))
		var mask:=resolve(f.get(&"mask")); masks.append(1. if mask!=null else 0.)
		if mask!=null: material.set_shader_parameter("mask_%d"%index,Field.texture(mask.values,true))
		var dimensions: Vector3=f.get(&"shape_size",Vector3.ONE); shapes.append(Vector4(dimensions.x,dimensions.y,dimensions.z,float(f.get(&"shape",0))))
		var rotation:=Quaternion.from_euler((f.get(&"shape_rotation",Vector3.ZERO) as Vector3)*PI/180.); rotations.append(Vector4(rotation.x,rotation.y,rotation.z,rotation.w)); edges.append(float(f.get(&"shape_edge",.05)))
		if enabled and int(f.get(&"mode",0)) in [4,5,7,8]:
			var texture:=Field.texture(f); material.set_shader_parameter("field_%d"%index,texture)
			if texture==null:
				modes[index].x=0.; fog.set_meta("fog_boundary_error","Field volume is unavailable. Choose a valid 3D texture or a closed Mesh resource.")
	for pair in [["field_mode",modes],["field_params",params],["field_direction",directions],["field_scale",scales],["field_offset",offsets],["field_color",colors],["field_threshold",thresholds],["field_value",uniform_values],["field_has_mask",masks]]: material.set_shader_parameter(pair[0],pair[1])
	material.set_shader_parameter("field_shape",shapes); material.set_shader_parameter("field_rotation",rotations); material.set_shader_parameter("field_edge",edges)
	material.set_shader_parameter("field_cloud_ground",cloud_ground)
	fog.set_meta("fog_status","Four appearance influences plus a density field. Anisotropy is controlled by World Environment. Custom shaders bypass built-in appearance.")

static func resolve(value: Variant) -> ActorObjectData:
	return ActorAnimation.resolve_reference(value) if value is ActorObjectReference else (value as ActorObjectData if value is ActorObjectData else null)
