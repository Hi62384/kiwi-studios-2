class_name KiwiModelModifiers
extends RefCounted
const TYPES := ["Mirror","Linear array","Radial array","Subdivision","Smooth","Solidify","Twist","Taper","Bevel"]

static func evaluate(component: KiwiModelComponent) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_modifiers").evaluate(component)
static func apply(mesh: KiwiModelMesh,settings: Dictionary) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_modifiers").apply(mesh,settings)
