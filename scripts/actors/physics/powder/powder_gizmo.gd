extends RefCounted
## Screen-space editor overlay, never included in rendered video.
static func draw(spatial: Node,runtime: KiwiPowderRuntime) -> void:
	_native_gizmo().draw(spatial,runtime)

static func box(lines: Array[PackedVector3Array],bounds: AABB,pose: Transform3D) -> void:
	_native_gizmo().box(lines,bounds,pose)

static func ring(lines: Array[PackedVector3Array],pose: Transform3D,half: Vector3,axis: int) -> void:
	_native_gizmo().ring(lines,pose,half,axis)


static func _native_gizmo() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_gizmo")
