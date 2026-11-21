class_name KiwiMorphDeformation
extends RefCounted
## Native triangulation and continuous triangle-area validation.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "morph_deformation")
static func append_pair(a: Array[Vector2], b: Array[Vector2], p: Vector2, q: Vector2) -> void: _native().call("append_pair", a, b, p, q)
static func triangulate(a: PackedVector2Array, b: PackedVector2Array) -> Dictionary: return _native().call("triangulate", a, b)
static func validate(a: PackedVector2Array, b: PackedVector2Array, indices: PackedInt32Array) -> Dictionary: return _native().call("validate", a, b, indices)
static func prepare(a: Dictionary, b: Dictionary, pins_a: PackedVector2Array, pins_b: PackedVector2Array, settings: Dictionary) -> Dictionary: return _native().call("prepare", a, b, pins_a, pins_b, settings)
