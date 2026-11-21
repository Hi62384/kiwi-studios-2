class_name KiwiGrowthActor
extends RefCounted
const APPEARANCE:=["root_color","tip_color","highlight_color","roughness","specular","secondary_highlight","highlight_shift","backlight","opacity","emission","variation","pattern_scale","pattern_rotation","pattern_mix","texture_scale","texture_offset","texture_rotation","bands","edge_softness","outline","shaft_color","feather_detail","iridescence","left_vane_color","right_vane_color","feather_pattern_color","feather_pattern_scale","feather_pattern_width","shaft_roughness"]
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","growth_actor")
static func extend_actor(definition: ActorDefinition) -> void: _native().call("extend_actor",definition)
static func initialize(actor: ActorData,data: KiwiSurfaceGrowthData) -> void: _native().call("initialize",actor,data)
static func apply(runtime: ActorRuntime,values: Dictionary) -> void: _native().call("apply",runtime,values)
