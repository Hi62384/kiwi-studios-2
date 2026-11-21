class_name KiwiMorphDistanceField
extends RefCounted
## Typed bridge; signed-distance propagation and pixel preparation run in C#.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "morph_distance_field")
static func build(image: Image, analysis: Dictionary, other_palette: Array) -> Image:
	return _native().call("build", image, analysis, other_palette)
static func propagate(field: PackedVector2Array, size: Vector2i) -> PackedVector2Array:
	return _native().call("propagate", field, size)
