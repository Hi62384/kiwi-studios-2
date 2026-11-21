class_name KiwiModelPrimitives
extends RefCounted
const SHAPES := ["Box","Sphere","Cylinder","Cone","Capsule","Plane","Torus","Prism","Gear","Pipe","Bolt","Arch","Stairs","Beam","Panel"]

static func defaults(kind: String) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_primitives").defaults(kind)
static func create(kind: String,parameters: Dictionary={}) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_primitives").create(kind,parameters)
static func box(size: Vector3) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_primitives").box(size)
static func prism(profile: PackedVector2Array,height: float,hole: float=0.,top_scale: float=1.) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_primitives").prism(profile,height,hole,top_scale)
