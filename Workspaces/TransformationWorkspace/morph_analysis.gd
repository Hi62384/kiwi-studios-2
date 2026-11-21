class_name KiwiMorphAnalysis
extends RefCounted
## Typed bridge to worker-local native analysis and correspondence preparation.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "morph_analysis")
static func analyze(image: Image) -> Dictionary: return _native().call("analyze", image)
static func signed_area(points: PackedVector2Array) -> float: return _native().call("signed_area", points)
static func regions(mask: PackedByteArray, size: Vector2i) -> Dictionary: return _native().call("regions", mask, size)
static func resample(points: PackedVector2Array, count: int) -> PackedVector2Array: return _native().call("resample", points, count)
static func match(a: Dictionary, b: Dictionary, count: int, alignment: String="Bounds") -> Dictionary: return _native().call("match", a, b, count, alignment)
static func landmarks(a: Dictionary, b: Dictionary) -> Array[Dictionary]: return _native().call("landmarks", a, b)
