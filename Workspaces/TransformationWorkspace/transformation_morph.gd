class_name KiwiTransformationMorph
extends RefCounted
const Analysis = preload("res://Workspaces/TransformationWorkspace/morph_analysis.gd")
const Deformation = preload("res://Workspaces/TransformationWorkspace/morph_deformation.gd")
const Field = preload("res://Workspaces/TransformationWorkspace/morph_distance_field.gd")
const GRID := 20
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_morph")
static func silhouette(image: Image) -> Dictionary: return _native().call("silhouette", image)
static func axis_map(value: float, lo_a: float, hi_a: float, lo_b: float, hi_b: float) -> float: return _native().call("axis_map", value, lo_a, hi_a, lo_b, hi_b)
static func mapped(point: Vector2, a: PackedVector2Array, b: PackedVector2Array) -> Vector2: return _native().call("mapped", point, a, b)
static func identity() -> Dictionary: return _native().call("identity")
static func prepare(image_a: Image, image_b: Image, pins_a: PackedVector2Array=PackedVector2Array(), pins_b: PackedVector2Array=PackedVector2Array(), settings: Dictionary={}, basis: Dictionary={}) -> Dictionary: return _native().call("prepare", image_a, image_b, pins_a, pins_b, settings, basis)
static func bounded(image: Image, limit: int) -> Image: return _native().call("bounded", image, limit)
