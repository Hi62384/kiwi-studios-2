class_name KiwiPhysicsCollisionWorld
extends RefCounted
## Offline collision queries only. This space is NEVER stepped by the engine.
var space := RID()
var bodies: Dictionary = {}
var owners: Dictionary = {}
var query_count := 0
func remove(id: String) -> void:
	_native_collision().remove(self,id)

func add_compound(id: String,shapes: Array,layer: int,mask: int) -> void:
	_native_collision().add_compound(self,id,shapes,layer,mask)

func reset() -> void:
	_native_collision().reset(self)

func create() -> void:
	_native_collision().create(self)

func add(id: String, shape: Shape3D, offset: Transform3D, layer: int, mask: int) -> void:
	_native_collision().add(self,id,shape,offset,layer,mask)

func place(id: String, transform: Transform3D, enabled: bool = true) -> void:
	_native_collision().place(self,id,transform,enabled)

func move(id: String, from: Transform3D, motion: Vector3, exclude: Array[String] = []) -> Dictionary:
	return _native_collision().move(self,id,from,motion,exclude)

func point_motion(id: String, from: Vector3, to: Vector3, radius: float, layer: int, mask: int, exclude: Array[String]) -> Dictionary:
	return _native_collision().point_motion(self,id,from,to,radius,layer,mask,exclude)

func _notification(what: int) -> void:
	# Script methods cannot be dispatched on a RefCounted during finalization.
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in bodies.values(): PhysicsServer3D.free_rid(entry.rid)
		if space.is_valid(): PhysicsServer3D.free_rid(space)

static func _native_collision() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","physics_collision_world")
