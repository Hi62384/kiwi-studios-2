class_name KiwiFluidSettings
extends RefCounted
const APPEARANCE:=["fluid_material","fluid_color","fluid_opacity","fluid_roughness","fluid_metallic","fluid_specular","fluid_emission","fluid_texture","fluid_normal","fluid_texture_scale","fluid_texture_offset","fluid_texture_rotation","fluid_texture_flow","fluid_texture_blend","fluid_normal_strength","fluid_surface_scale","fluid_surface_level","fluid_foam","fluid_foam_color","fluid_foam_duration"]
const PRESETS:=[
	{"fluid_density":1000.0,"fluid_viscosity":.15,"fluid_cohesion":.8,"fluid_tension":.4,"fluid_boundary_friction":.08,"fluid_color":Color(.12,.46,.8),"fluid_roughness":.16,"fluid_foam":.45,"fluid_emission":0.0,"fluid_opacity":.96},
	{"fluid_density":870.0,"fluid_viscosity":6.0,"fluid_cohesion":1.5,"fluid_tension":.7,"fluid_boundary_friction":.2,"fluid_color":Color(.16,.11,.025),"fluid_roughness":.2,"fluid_foam":.03,"fluid_emission":0.0,"fluid_opacity":.99},
	{"fluid_density":1420.0,"fluid_viscosity":60.0,"fluid_cohesion":4.0,"fluid_tension":1.5,"fluid_boundary_friction":.5,"fluid_color":Color(.85,.33,.025),"fluid_roughness":.21,"fluid_foam":0.0,"fluid_emission":0.0,"fluid_opacity":.99},
	{"fluid_density":1100.0,"fluid_viscosity":35.0,"fluid_cohesion":7.0,"fluid_tension":2.5,"fluid_boundary_friction":.35,"fluid_color":Color(.25,.8,.12),"fluid_roughness":.3,"fluid_foam":.1,"fluid_emission":0.0,"fluid_opacity":.97},
	{"fluid_density":2700.0,"fluid_viscosity":90.0,"fluid_cohesion":5.0,"fluid_tension":1.8,"fluid_boundary_friction":.6,"fluid_color":Color(1,.15,.015),"fluid_roughness":.6,"fluid_foam":0.0,"fluid_emission":2.0,"fluid_temperature":1100.0,"fluid_opacity":1.0}]
static func effective(values: Dictionary) -> Dictionary:
	return _native_settings().effective(values)

static func preset(model: RefCounted,actor: ActorData,index: int) -> void:
	_native_settings().preset(model,actor,index)

static func assign(model: RefCounted,actor: ActorData,values: Dictionary) -> void:
	_native_settings().assign(model,actor,values)


static func _native_settings() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_settings")
