class_name KiwiPowderMaterial
extends RefCounted
## A reusable recipe, not a second simulation configuration. Physical defaults
## are adopted explicitly; the actor's existing physical controls stay authoritative.
const NAMES := ["Sand", "Snow", "Dirt", "Gravel", "Dust", "Salt", "Sugar"]
const TRANSPORT := ["powder_deposition","powder_adhesion","powder_settling","powder_coating","powder_deposit_compaction","powder_displacement","powder_displacement_resistance","powder_reactivation","powder_erosion","powder_erosion_resistance","powder_wind_erosion","powder_fluid_erosion","powder_airborne","powder_airborne_threshold"]
const PHYSICS := ["powder_radius","powder_size_variation","powder_density","powder_friction","powder_cohesion","powder_flowability","powder_restitution","powder_damping","powder_compaction","powder_wind","powder_advanced_material","powder_static_friction","powder_dynamic_friction","powder_rolling","powder_gravity","powder_bond_range","powder_contact_damping","powder_air_drag","powder_turbulence","powder_fluid"]
const VISUAL := ["powder_color","powder_secondary","powder_color_variation","powder_roughness","powder_roughness_variation","powder_metallic","powder_specular","powder_opacity","powder_grain_shape","powder_shape_variation","powder_rotation_variation","powder_visual_seed","powder_variants","powder_custom_mesh","powder_custom_mesh_2","powder_custom_mesh_3","powder_render_detail","powder_texture","powder_normal","powder_roughness_texture","powder_texture_scale","powder_texture_offset","powder_texture_rotation","powder_texture_blend","powder_texture_tint","powder_detail_intensity","powder_normal_strength","powder_style","powder_surface_material"]

const FIELD_ROWS=[
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

static func fields() -> Array[ActorProperty]:
	var result: Array[ActorProperty]=[]
	result.assign(_native_material().fields())
	return result

static func definition() -> ActorObjectDefinition:
	return _native_material().definition()

static func preset(index: int) -> ActorObjectData:
	return _native_material().preset(index)

static func appearance(values: Dictionary) -> Dictionary:
	return _native_material().appearance(values)

static func capture(actor: ActorData) -> ActorObjectData:
	return _native_material().capture(actor)

static func apply(model: ActorTimeline,actors: Array[ActorData],ref: ActorObjectReference,mode: int=0) -> void:
	_native_material().apply(model,actors,ref,mode)

static func link(model: ActorTimeline,actors: Array[ActorData],enabled: bool) -> void:
	_native_material().link(model,actors,enabled)

static func physical_path(path: PackedStringArray) -> bool:
	return _native_material().physical_path(path)


static func _native_material() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_material")
