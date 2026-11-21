extends RefCounted
## Bounded height cache over the existing offline timeline collision world.
static var cache: Dictionary={}
static func prepare(controller: RefCounted,pose: Transform3D,size: Vector3,settings: Dictionary) -> Dictionary:
	return _native().prepare(controller,pose,size,settings)
static func sample_height(image: Image,unit: Vector3) -> float:
	return _native().sample_height(image,unit)
static func sync(runtime: Node,material: ShaderMaterial) -> void:
	_native().sync(runtime,material)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_ground")
