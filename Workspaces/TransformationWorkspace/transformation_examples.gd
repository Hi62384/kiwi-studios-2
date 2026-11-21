class_name KiwiTransformationExamples
extends RefCounted
const NAMES := ["Blinking eye","Talking mouth","Bouncing ball","Layered face","Bleeding cut"]
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_examples")
static func image(kind: String, amount: float=1.) -> Image: return _native().call("image", kind, amount)
static func component(document: KiwiTransformationImage2D, title: String, position: Vector2, dimensions: Vector2) -> KiwiTransformationComponent: return _native().call("component", document, title, position, dimensions)
static func state(item: KiwiTransformationComponent, title: String, bitmap: Image) -> KiwiTransformationState: return _native().call("state", item, title, bitmap)
static func key(item: KiwiTransformationComponent, at: float, state: KiwiTransformationState, mode: String="Smooth morph") -> KiwiTransformationKey: return _native().call("key", item, at, state, mode)
static func finish(item: KiwiTransformationComponent, states: Array[KiwiTransformationState]) -> void: _native().call("finish", item, states)
static func create(title: String) -> KiwiTransformationImage2D: return _native().call("create", title)
