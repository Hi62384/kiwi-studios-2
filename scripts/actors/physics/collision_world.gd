class_name KiwiPhysicsCollisionWorld
extends RefCounted
## Offline collision queries only. This space is NEVER stepped by the engine.
var space := RID()
var bodies: Dictionary = {}
var owners: Dictionary = {}
var query_count := 0
func reset() -> void:
	for entry: Dictionary in bodies.values(): PhysicsServer3D.free_rid(entry.rid)
	bodies.clear(); owners.clear()
	if space.is_valid(): PhysicsServer3D.free_rid(space)
	space = RID()
func create() -> void:
	reset(); space = PhysicsServer3D.space_create(); PhysicsServer3D.space_set_active(space, false)
func add(id: String, shape: Shape3D, offset: Transform3D, layer: int, mask: int) -> void:
	if not space.is_valid(): create()
	var rid := PhysicsServer3D.body_create()
	# These are query colliders, not simulated native bodies. Kinematic RID
	# transforms are deferred until a physics tick, which this space MUST NOT run.
	# Static RID transforms update immediately, and body_test_motion accepts them.
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(rid, space)
	PhysicsServer3D.body_add_shape(rid, shape.get_rid(), offset)
	PhysicsServer3D.body_set_collision_layer(rid, layer)
	PhysicsServer3D.body_set_collision_mask(rid, mask)
	bodies[id] = {"rid": rid, "shape": shape, "offset": offset}; owners[rid] = id
func place(id: String, transform: Transform3D, enabled: bool = true) -> void:
	if not bodies.has(id): return
	var scale := transform.basis.get_scale().abs().max(Vector3.ONE * .0001)
	PhysicsServer3D.body_set_shape_transform(bodies[id].rid, 0, Transform3D(Basis.from_scale(scale), Vector3.ZERO) * bodies[id].offset)
	PhysicsServer3D.body_set_state(bodies[id].rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(transform.basis.orthonormalized(), transform.origin))
	PhysicsServer3D.body_set_shape_disabled(bodies[id].rid, 0, not enabled)
func move(id: String, from: Transform3D, motion: Vector3, exclude: Array[String] = []) -> Dictionary:
	if not bodies.has(id): return {"travel": motion, "hits": []}
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = Transform3D(from.basis.orthonormalized(), from.origin); parameters.motion = motion; parameters.margin = .002; parameters.max_collisions = 4; parameters.recovery_as_collision = true
	# A tiny probe ensures contact detection when an animated collider reaches a
	# stationary gravity-free body. A miss still returns the original zero motion.
	if motion.is_zero_approx(): parameters.motion=Vector3.DOWN*.0001
	for other in exclude:
		if bodies.has(other): parameters.exclude_bodies.append(bodies[other].rid)
	var result := PhysicsTestMotionResult3D.new(); query_count += 1
	if not PhysicsServer3D.body_test_motion(bodies[id].rid, parameters, result): return {"travel": motion, "hits": []}
	var hits := []
	for i in result.get_collision_count():
		hits.append({"normal": result.get_collision_normal(i), "point": result.get_collision_point(i), "depth": result.get_collision_depth(i), "actor": owners.get(result.get_collider_rid(i), "")})
	return {"travel": result.get_travel(), "hits": hits}
func point_motion(id: String, from: Vector3, to: Vector3, radius: float, layer: int, mask: int, exclude: Array[String]) -> Dictionary:
	var probe := "@probe:" + str(radius) + ":" + str(mask)
	if not bodies.has(probe):
		var shape := SphereShape3D.new(); shape.radius = maxf(.002, radius)
		add(probe, shape, Transform3D.IDENTITY, 0, mask)
	var ignored: Array[String] = exclude.duplicate(); ignored.append(id)
	var result := move(probe, Transform3D(Basis.IDENTITY, from), to - from, ignored)
	return {"position": from + result.travel, "hits": result.hits}
func _notification(what: int) -> void:
	# Script methods cannot be dispatched on a RefCounted during finalization.
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in bodies.values(): PhysicsServer3D.free_rid(entry.rid)
		if space.is_valid(): PhysicsServer3D.free_rid(space)
