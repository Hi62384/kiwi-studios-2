class_name KiwiFluidDefinition
extends RefCounted
const PROPERTY_ROWS=[
	["position","Position",Vector3.ZERO,"Transform"],
	["rotation","Rotation",Vector3.ZERO,"Transform"],
	["scale","Scale",Vector3.ONE,"Transform"],
	["physics","Physics",{"enabled":true,"type":6,"damping":.02},"Fluid",{"inspector_hidden":true}],
	["fluid_preset","Material preset",0,"Fluid",{"choices":["Water","Oil","Honey / Syrup","Slime","Lava"],"refresh_inspector":true}],
	["fluid_density","Density (kg/m³)",1000.0,"Fluid",{"min":1.0,"max":20000.0,"step":1.0}],
	["fluid_viscosity","Viscosity",.15,"Fluid",{"min":0.0,"max":150.0,"step":.1}],
	["fluid_cohesion","Cohesion",.8,"Fluid",{"min":0.0,"max":15.0}],
	["fluid_tension","Surface tension",.4,"Fluid",{"min":0.0,"max":8.0}],
	["fluid_quality","Quality",1,"Quality",{"choices":["Fast","Balanced","Detailed"],"refresh_inspector":true}],
	["fluid_spacing","Base particle spacing (m)",.22,"Quality",{"min":.025,"max":2.0,"step":.01}],
	["fluid_budget","Maximum particles",1024,"Quality",{"min":16,"max":4096,"step":1}],
	["fluid_iterations","Base pressure iterations",3,"Quality",{"min":1,"max":8,"step":1}],
	["fluid_substeps","Minimum substeps",1,"Quality",{"min":1,"max":4,"step":1}],
	["fluid_compliance","Pressure compliance",.02,"Quality",{"min":.0001,"max":1.0,"step":.001}],
	["fluid_max_speed","Maximum speed (m/s)",20.0,"Quality",{"min":.1,"max":100.0}],
	["fluid_source_mode","Source",0,"Source",{"choices":["Finite volume","Emitter","Volume + emitter"],"refresh_inspector":true}],
	["fluid_shape","Volume shape",0,"Source",{"choices":["Box","Sphere / ellipsoid","Cylinder","Closed mesh actor"],"refresh_inspector":true}],
	["fluid_dimensions","Dimensions (m)",Vector3(1,1.2,1),"Source"],
	["fluid_mesh_actor","Closed mesh actor","","Source",{"actor_reference":true,"visible_when":{"property":"fluid_shape","values":[3]}}],
	["fluid_emit_shape","Nozzle shape",0,"Source",{"choices":["Disk","Box","Sphere"],"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_rate","Particles / source second",40.0,"Source",{"min":0.0,"max":2000.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_start","Emission start (s)",0.0,"Source",{"min":0.0,"max":86400.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_end","Emission end (-1 = ongoing)",-1.0,"Source",{"min":-1.0,"max":86400.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_supply","Total {"property":"fluid_source_mode","values":[1,2]} particles (0 = unlimited)",0,"Source",{"min":0,"max":1000000,"step":1,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_radius","Nozzle radius (m)",.12,"Source",{"min":.01,"max":5.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_direction","Nozzle direction",Vector3.DOWN,"Source",{"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_emit_speed","Nozzle speed (m/s)",1.0,"Source",{"min":0.0,"max":100.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_spread","Nozzle spread",.08,"Source",{"min":0.0,"max":1.0,"visible_when":{"property":"fluid_source_mode","values":[1,2]}}],
	["fluid_characters","Animated bone collision proxies",true,"Interactions"],
	["fluid_deformables","Soft / cloth point proxies",false,"Interactions"],
	["fluid_boundary_friction","Boundary friction",.08,"Interactions",{"min":0.0,"max":1.0}],
	["fluid_restitution","Boundary bounce",.02,"Interactions",{"min":0.0,"max":1.0}],
	["fluid_material","Custom material",null,"Appearance",{},&"material"],
	["fluid_color","Color",Color(.12,.46,.8,1),"Appearance"],
	["fluid_opacity","Opacity",.96,"Appearance",{"min":0.0,"max":1.0}],
	["fluid_roughness","Roughness",.16,"Appearance",{"min":0.0,"max":1.0}],
	["fluid_metallic","Metallic",0.0,"Appearance",{"min":0.0,"max":1.0}],
	["fluid_specular","Specular",.7,"Appearance",{"min":0.0,"max":1.0}],
	["fluid_emission","Glow",0.0,"Appearance",{"min":0.0,"max":8.0}],
	["fluid_texture","Color / pattern image",null,"Texture",{},&"image"],
	["fluid_normal","Normal detail image",null,"Texture",{},&"image"],
	["fluid_texture_scale","Texture scale",1.0,"Texture",{"min":.01,"max":100.0}],
	["fluid_texture_offset","Texture offset",Vector3.ZERO,"Texture"],
	["fluid_texture_rotation","Texture rotation (degrees)",0.0,"Texture"],
	["fluid_texture_flow","Texture flow (m/s)",Vector3(.03,-.05,.02),"Texture"],
	["fluid_texture_blend","Texture blend",1.0,"Texture",{"min":0.0,"max":1.0}],
	["fluid_normal_strength","Normal strength",.25,"Texture",{"min":0.0,"max":2.0}],
	["fluid_surface_scale","Surface cell scale",1.0,"Surface",{"min":.6,"max":1.6}],
	["fluid_surface_level","Surface level",.65,"Surface",{"min":.2,"max":1.3}],
	["fluid_foam","Foam amount",.45,"Surface",{"min":0.0,"max":2.0}],
	["fluid_foam_color","Foam color",Color(.94,.98,1),"Surface"],
	["fluid_foam_duration","Foam duration (s)",1.2,"Surface",{"min":.05,"max":10.0}],
	["fluid_temperature","Temperature (°C)",20.0,"Fluid",{"min":-100.0,"max":2000.0,"visible_when":{"property":"fluid_preset","values":[4]}}]
]
static func create() -> ActorDefinition:
	return _native_definition().create(PROPERTY_ROWS)

static func add(d: ActorDefinition,key: String,title: String,value: Variant,group: String,hints: Dictionary={},object_type: StringName=&"") -> void:
	_native_definition().add(d,key,title,value,group,hints,object_type)


static func _native_definition() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_definition")
