extends RefCounted
## Native per-light and per-geometry controls, shared by ordinary and fog lighting.
const LIGHT_ROWS := [["volumetric_fog_energy","Volumetric fog energy",1.,0.,32.],["shadow_bias","Shadow bias",.1,0.,16.],["shadow_normal_bias","Shadow normal bias",2.,0.,16.],["shadow_opacity","Shadow opacity",1.,0.,1.],["shadow_blur","Shadow softness",1.,0.,8.],["light_size","Light source size",0.,0.,10.],["attenuation","Distance attenuation",1.,.01,16.],["spot_attenuation","Cone attenuation",1.,.01,16.]]
const ENVIRONMENT_ROWS := [["volumetric_fog_temporal_reprojection_enabled","Temporal reprojection",true,{}],["volumetric_fog_temporal_reprojection_amount","Temporal history strength",.9,{"min":0.,"max":.99}],["volumetric_fog_ambient_inject","Ambient illumination injection",0.,{"min":0.,"max":16.}]]
static func extend_actor(d: ActorDefinition) -> void:
	_native().extend_actor(d)

static func extend_environment(d: ActorObjectDefinition) -> void:
	_native().extend_environment(d)

static func apply_light(light: Light3D,v: Dictionary) -> void:
	_native().apply_light(light,v)

static func apply_geometry(runtime: Node,v: Dictionary) -> void:
	_native().apply_geometry(runtime,v)

static func visit_geometry(node: Node,owner: Node,mode: int) -> void:
	_native().visit_geometry(node,owner,mode)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_lighting")
