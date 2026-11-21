extends RefCounted
const RESOLUTIONS:=[8,12,16,24]
const MOTION_ROWS := [
		["fog_wind","Wind velocity (m/s)",Vector3.ZERO,"Wind",{}],
		["fog_wind_influence","Wind influence",1.,"Wind",{"min":0.,"max":8.}],
		["fog_gust_strength","Gust strength",0.,"Wind",{"min":0.,"max":8.}],
		["fog_gust_frequency","Gust frequency",1.,"Wind",{"min":0.,"max":16.}],
		["fog_turbulence","Turbulence acceleration",0.,"Turbulence",{"min":0.,"max":32.}],
		["fog_turbulence_scale","Turbulence scale (m)",1.,"Turbulence",{"min":.01,"max":1000.}],
		["fog_turbulence_frequency","Turbulence frequency",1.,"Turbulence",{"min":0.,"max":16.}],
		["fog_seed","Motion seed",1,"Turbulence",{"no_keyframes":true}],
		["fog_procedural_rotation","Procedural rotation (°/s)",Vector3.ZERO,"Procedural detail",{}],
		["fog_expansion","Expansion velocity",0.,"Transport",{"min":0.,"max":32.}],
		["fog_diffusion","Diffusion / mixing (m²/s)",0.,"Transport",{"min":0.,"max":4.}],
		["fog_dissipation","Density decay (1/s)",0.,"Transport",{"min":0.,"max":32.}],
		["fog_buoyancy","Buoyancy acceleration",0.,"Transport",{"min":-32.,"max":32.}],
		["fog_velocity_damping","Velocity damping",.1,"Transport",{"min":0.,"max":16.}],
		["fog_quality","Simulation quality",0,"Domain",{"choices":["Fast · 8³","Balanced · 12³","Detailed · 16³","Final · 24³","Custom"],"no_keyframes":true,"refresh_inspector":true}],
		["fog_resolution","Custom resolution",16,"Domain",{"min":4,"max":32,"no_keyframes":true}],
		["fog_initial","Initial concentration",0,"Domain",{"choices":["Authored density field","Empty · use sources"],"no_keyframes":true}],
		["fog_domain_behavior","Domain behavior",0,"Domain",{"choices":["Fixed world domain","Move domain with actor"],"no_keyframes":true,"tooltip":"A fixed domain retains previously emitted fog in world space. Moving emitters are evaluated separately."}],
		["fog_boundaries","Domain boundaries",0,"Domain",{"choices":["Open · concentration can leave","Sealed"],"no_keyframes":true}],
		["fog_pressure_iterations","Pressure iterations",2,"Domain",{"min":0,"max":24,"no_keyframes":true}],
		["fog_max_density","Concentration maximum",32.,"Domain",{"min":.1,"max":256.}],
		["fog_obstacles","Obstacle interaction",true,"Obstacles",{}],
		["fog_obstacle_motion","Moving boundary influence",1.,"Obstacles",{"min":0.,"max":4.}],
		["fog_character_proxies","Character / deformable proxies",true,"Obstacles",{}]
]
const EMITTER_ROWS := [
		["enabled","Enabled",true,{}],["mode","Emission",0,{"choices":["Continuous","Burst"]}],
		["shape","Source shape",1,{"choices":["Point","Sphere","Box","Disk","Cone","Closed mesh volume"]}],
		["position","Source position",Vector3.ZERO,{}],["size","Source size (m)",Vector3.ONE*.5,{}],
		["direction","Direction",Vector3.UP,{}],["spread","Spread (°)",0.,{"min":0.,"max":180.}],
		["rate","Concentration volume / second",.2,{"min":0.,"max":1000.}],
		["burst","Burst concentration volume",1.,{"min":0.,"max":1000.}],
		["start","Start (source seconds)",0.,{}],["end","End (-1 = no stop)",-1.,{}],
		["velocity","Initial velocity (m/s)",Vector3.UP,{}],["inherit_velocity","Inherit source movement",true,{}],
		["seed","Seed",1,{"no_keyframes":true}],["source_actor","Follow actor","",{"fog_actor_link":true,"no_keyframes":true,"refresh_inspector":true}],["source_bone","Bone (optional)","",{"no_keyframes":true}]
]
const VELOCITY_ROWS := [
		["enabled","Enabled",true,{}],["type","Influence",0,{"choices":["Directional","Radial outward","Radial inward","Vortex","Coherent turbulence"]}],
		["position","Center",Vector3.ZERO,{}],["direction","Direction / vortex axis",Vector3.UP,{}],
		["radius","Radius (m)",2.,{"min":.01,"max":10000.}],["strength","Acceleration (m/s²)",1.,{"min":-100.,"max":100.}],["falloff","Falloff",1.,{"min":0.,"max":16.}],
		["source_actor","Follow actor","",{"fog_actor_link":true,"no_keyframes":true,"refresh_inspector":true}],["source_bone","Bone (optional)","",{"no_keyframes":true}]
]
static func extend_actor(d: ActorDefinition) -> void:
	_native().extend_actor(d)

static func emitter_definition() -> ActorObjectDefinition:
	return _native().emitter_definition()

static func velocity_definition() -> ActorObjectDefinition:
	return _native().velocity_definition()

static func add_rows(d: ActorObjectDefinition,rows: Array) -> void:
	_native().add_rows(d,rows)

static func resolution(values: Dictionary) -> int:
	return _native().resolution(values)

static func physical_path(path: PackedStringArray) -> bool:
	return _native().physical_path(path)

static func content(value: Variant,depth: int=0) -> Variant:
	return _native().content(value,depth)

static func dependencies(actor: ActorData) -> Array[String]:
	var result: Array[String]=[]
	result.assign(_native().dependencies(actor))
	return result

static func remap_actor(actor: ActorData,ids: Dictionary,clear_external: bool=false) -> void:
	_native().remap_actor(actor,ids,clear_external)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_motion_definition")
