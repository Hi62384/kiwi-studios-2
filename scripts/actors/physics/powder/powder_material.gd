class_name KiwiPowderMaterial
extends RefCounted
## A reusable recipe, not a second simulation configuration. Physical defaults
## are adopted explicitly; the actor's existing physical controls stay authoritative.
const NAMES := ["Sand", "Snow", "Dirt", "Gravel", "Dust", "Salt", "Sugar"]
const TRANSPORT := ["powder_deposition","powder_adhesion","powder_settling","powder_coating","powder_deposit_compaction","powder_displacement","powder_displacement_resistance","powder_reactivation","powder_erosion","powder_erosion_resistance","powder_wind_erosion","powder_fluid_erosion","powder_airborne","powder_airborne_threshold"]
const PHYSICS := ["powder_radius","powder_size_variation","powder_density","powder_friction","powder_cohesion","powder_flowability","powder_restitution","powder_damping","powder_compaction","powder_wind","powder_advanced_material","powder_static_friction","powder_dynamic_friction","powder_rolling","powder_gravity","powder_bond_range","powder_contact_damping","powder_air_drag","powder_turbulence","powder_fluid"]
const VISUAL := ["powder_color","powder_secondary","powder_color_variation","powder_roughness","powder_roughness_variation","powder_metallic","powder_specular","powder_opacity","powder_grain_shape","powder_shape_variation","powder_rotation_variation","powder_visual_seed","powder_variants","powder_custom_mesh","powder_custom_mesh_2","powder_custom_mesh_3","powder_render_detail","powder_texture","powder_normal","powder_roughness_texture","powder_texture_scale","powder_texture_offset","powder_texture_rotation","powder_texture_blend","powder_texture_tint","powder_detail_intensity","powder_normal_strength","powder_style","powder_surface_material"]

static func fields() -> Array[ActorProperty]:
	var result: Array[ActorProperty]=[]
	var rows := [
		["powder_color","Base color",Color(.79,.61,.34),{}],
		["powder_secondary","Secondary color",Color(.94,.81,.56),{}],
		["powder_color_variation","Color variation",.4,{"min":0.0,"max":1.0}],
		["powder_roughness","Roughness",.85,{"min":0.0,"max":1.0}],
		["powder_roughness_variation","Roughness variation",.15,{"min":0.0,"max":1.0}],
		["powder_metallic","Metallic",0.0,{"min":0.0,"max":1.0}],
		["powder_specular","Specular",.4,{"min":0.0,"max":1.0}],
		["powder_opacity","Opacity",1.0,{"min":0.0,"max":1.0}],
		["powder_grain_shape","Grain shape",1,{"choices":["Rounded","Angular","Irregular","Crystal-like","Custom mesh"],"no_keyframes":true}],
		["powder_shape_variation","Shape variation",.25,{"min":0.0,"max":1.0}],
		["powder_rotation_variation","Rotation variation",1.0,{"min":0.0,"max":1.0}],
		["powder_visual_seed","Appearance seed",17,{"no_keyframes":true}],
		["powder_variants","Geometry variants",3,{"min":1,"max":8,"step":1,"no_keyframes":true}],
		["powder_render_detail","Geometry detail",1,{"choices":["Low / distant grains","Balanced","Detailed close-up"],"no_keyframes":true}],
		["powder_texture_scale","Texture scale",Vector2.ONE,{}],
		["powder_texture_offset","Texture offset",Vector2.ZERO,{}],
		["powder_texture_rotation","Texture rotation (°)",0.0,{}],
		["powder_texture_blend","Texture blend",1.0,{"min":0.0,"max":1.0}],
		["powder_texture_tint","Texture tint",Color.WHITE,{}],
		["powder_detail_intensity","Procedural mineral detail",.2,{"min":0.0,"max":1.0}],
		["powder_normal_strength","Normal strength",.5,{"min":0.0,"max":2.0}],
		["powder_style","Shading",0,{"choices":["Lit / realistic","Flat / stylized"],"no_keyframes":true}]
	]
	for row in rows:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],not row[3].get("no_keyframes",false)); p.options.merge(row[3]); p.options.group="Appearance"; result.append(p)
	for key in ["powder_custom_mesh","powder_custom_mesh_2","powder_custom_mesh_3"]:
		var p:=ActorProperty.create(StringName(key),["Custom grain mesh","Alternate mesh 2","Alternate mesh 3"][["powder_custom_mesh","powder_custom_mesh_2","powder_custom_mesh_3"].find(key)],"")
		p.options.merge({"group":"Geometry","file_picker":true,"extensions":["tres","res","mesh"],"native_resource_types":["Mesh"],"file_resource_mode":"uneditable","visible_when":{"property":"powder_grain_shape","values":[4]}}); result.append(p)
	for key in ["powder_texture","powder_normal","powder_roughness_texture","powder_surface_material"]:
		var p:=ActorProperty.create(StringName(key),{"powder_texture":"Albedo texture","powder_normal":"Normal / detail texture","powder_roughness_texture":"Roughness texture","powder_surface_material":"Surface material override"}[key],null)
		p.object_type=&"material" if key=="powder_surface_material" else &"image"
		p.options.merge({"group":"Textures" if key!="powder_surface_material" else "Appearance","accepted_object_types":["material","shader_material","natural_material"] if key=="powder_surface_material" else ["image","noise_image"]}); result.append(p)
	return result

static func definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"powder_material"; d.display_name="Powder Material"
	for row in [["material_name","Name","Sand"],["material_id","Material ID",""],["preset_origin","Original preset","Sand"]]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2]); p.options.group="Material"; p.options.no_keyframes=true; d.properties.append(p)
	d.properties.append_array(fields())
	for p in KiwiPowderDefinition.create().properties:
		if str(p.id) in PHYSICS+TRANSPORT:
			var copy:=p.duplicate(true) as ActorProperty; copy.options.group="Physics defaults — apply to adopt"; copy.options.erase("visible_when"); copy.options.erase("advanced"); copy.options.no_keyframes=true; d.properties.append(copy)
	return d

static func preset(index: int) -> ActorObjectData:
	index=clampi(index,0,NAMES.size()-1)
	var data:=ActorObjectData.new(); data.type_id=&"powder_material"
	for p in fields(): data.values[p.id]=p.create_default()
	# SI-scale illustrative artistic recipes, not experimentally calibrated data.
	var colors:=[Color("c4a069"),Color("e4f1ff"),Color("60402b"),Color("666c70"),Color("a3998b"),Color("f5f8ff"),Color("f6edcf")]
	var seconds:=[Color("eed6a0"),Color.WHITE,Color("a58756"),Color("b7afa0"),Color("c3b6a1"),Color("cbd9e9"),Color.WHITE]
	data.values.merge({&"material_name":NAMES[index],&"material_id":ActorData.new_id(),&"preset_origin":NAMES[index],&"powder_color":colors[index],&"powder_secondary":seconds[index],&"powder_grain_shape":[1,3,2,2,0,3,3][index],&"powder_shape_variation":[.25,.6,.85,.65,.2,.12,.4][index],&"powder_color_variation":[.4,.25,.7,.8,.25,.3,.25][index],&"powder_roughness":[.85,.38,.97,.9,1.,.2,.3][index],&"powder_specular":[.4,.8,.15,.4,.1,.9,.8][index],&"powder_detail_intensity":[.3,.08,.65,.45,.05,.05,.1][index],&"powder_radius":[.055,.07,.065,.11,.022,.045,.05][index],&"powder_size_variation":[.2,.3,.45,.5,.25,.15,.25][index],&"powder_density":[1600.,350.,1350.,2600.,300.,2160.,1580.][index],&"powder_friction":[.6,.8,.85,1.1,.4,.4,.45][index],&"powder_cohesion":[.0,.08,.035,0.,.001,0.,.002][index],&"powder_flowability":[.65,.2,.35,.2,.8,.85,.75][index],&"powder_restitution":[.03,.01,.02,.12,.01,.12,.08][index],&"powder_compaction":[.97,.65,.85,.99,.7,.98,.97][index],&"powder_wind":[1.,2.,.8,.15,5.,.7,.8][index],&"powder_air_drag":[.47,.8,.65,.4,1.2,.5,.55][index],&"powder_damping":.08,&"powder_gravity":1.,&"powder_advanced_material":false},true)
	return data

static func appearance(values: Dictionary) -> Dictionary:
	var result:=values.duplicate()
	var ref: Variant=values.get(&"powder_material")
	if values.get(&"powder_link_appearance",false) and ref is ActorObjectReference:
		var data:=ActorAnimation.resolve_reference(ref)
		if data!=null:
			for key in VISUAL:
				if data.values.has(StringName(key)): result[StringName(key)]=data.values[StringName(key)]
	return result

static func capture(actor: ActorData) -> ActorObjectData:
	var data:=preset(0); var values:=appearance(actor.values)
	data.values[&"material_name"]=actor.display_name+" material"; data.values[&"preset_origin"]="Custom"
	for key in VISUAL+PHYSICS+TRANSPORT:
		if values.has(StringName(key)): data.values[StringName(key)]=ActorData.copy_value(values[StringName(key)])
	return data

static func apply(model: ActorTimeline,actors: Array[ActorData],ref: ActorObjectReference,mode: int=0) -> void:
	var data:=ActorAnimation.resolve_reference(ref) if ref!=null else null
	var before:=[]; var after:=[]
	for actor in actors:
		if actor.type_id!=&"powder": continue
		before.append({"actor":actor,"values":actor.values.duplicate(true)})
		var values:=actor.values.duplicate(true)
		if mode!=2:
			values[&"powder_material"]=ref.copy_reference() if ref!=null else null
			values[&"powder_link_appearance"]=data!=null
			if data!=null:
				for key in VISUAL:
					if data.values.has(StringName(key)): values[StringName(key)]=ActorData.copy_value(data.values[StringName(key)])
		if mode!=1 and data!=null:
			for key in PHYSICS+TRANSPORT:
				if data.values.has(StringName(key)): values[StringName(key)]=data.values[StringName(key)]
			values[&"powder_spacing"]=maxf(float(values.powder_spacing),float(values.powder_radius)*2*(1+float(values.powder_size_variation))*1.08)
		after.append({"actor":actor,"values":values})
	model.history.create_action("Powder material: "+["appearance + physics","appearance only","physics only"][mode])
	model.history.add_do_method(KiwiPowderSettings.assign.bind(weakref(model),after)); model.history.add_undo_method(KiwiPowderSettings.assign.bind(weakref(model),before)); model.history.commit_action()

static func link(model: ActorTimeline,actors: Array[ActorData],enabled: bool) -> void:
	var before:=[]; var after:=[]
	for actor in actors:
		before.append({"actor":actor,"values":actor.values.duplicate(true)})
		var values:=actor.values.duplicate(true)
		if not enabled:
			var current:=appearance(actor.values)
			for key in VISUAL:
				if current.has(StringName(key)): values[StringName(key)]=ActorData.copy_value(current[StringName(key)])
		values[&"powder_link_appearance"]=enabled and values.get(&"powder_material")!=null; after.append({"actor":actor,"values":values})
	model.history.create_action("Powder material appearance link"); model.history.add_do_method(KiwiPowderSettings.assign.bind(weakref(model),after)); model.history.add_undo_method(KiwiPowderSettings.assign.bind(weakref(model),before)); model.history.commit_action()

static func physical_path(path: PackedStringArray) -> bool:
	# Resource physics are recipe defaults. Only the actor's adopted coefficients
	# affect trajectories; nested appearance animations are cache-independent.
	return not path.is_empty() and not (path[0] in VISUAL or path[0] in ["powder_material","powder_link_appearance","powder_preset","powder_show_source"])
