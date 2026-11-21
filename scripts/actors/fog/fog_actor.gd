extends RefCounted
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const SURFACE=preload("res://scripts/actors/fog/fog_surface.gdshader")

const APPEARANCE_UNIFORMS := [["render_style",0],["stylization",1.],["shading_bands",3],["shadow_tint",Color(.35,.42,.55)],["highlight",1.],["cloud_lighting",false],["cloud_shadow_strength",1.],["silver_lining",0.]]
const MAPPED_UNIFORMS := [["density_multiplier","density_multiplier",1.],["contrast","contrast",1.],["density_offset","offset",0.],["threshold","threshold",0.],["maximum_density","maximum",64.],["opacity","opacity",1.],["scattering","scattering",1.],["absorption","absorption",0.],["secondary","secondary",Color.WHITE],["gradient_mode","gradient",0],["gradient_direction","direction",Vector3.UP],["world_mapping","world_space",false],["texture_scale","texture_scale",Vector3.ONE],["texture_offset","texture_offset",Vector3.ZERO],["texture_mapping","texture_mapping",0],["texture_strength","texture_strength",1.]]

static func extend_actor(d: ActorDefinition) -> void:
	_native().extend_actor(d)

static func global_definition(local: ActorDefinition) -> ActorDefinition:
	return _native().global_definition(local)

static func apply(runtime: Node,values: Dictionary) -> void:
	_native().apply(runtime,values)

static func resolve(value: Variant) -> ActorObjectData:
	return _native().resolve(value)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_actor")
