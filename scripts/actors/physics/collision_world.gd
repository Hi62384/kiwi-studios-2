class_name KiwiPhysicsCollisionWorld
extends RefCounted
## Offline collision queries only. This space is NEVER stepped by the engine.
var space := RID()
var bodies: Dictionary = {}
var owners: Dictionary = {}
var query_count := 0
func remove(id: String) -> void:
	if not bodies.has(id): return
	owners.erase(bodies[id].rid); PhysicsServer3D.free_rid(bodies[id].rid); bodies.erase(id)
func add_compound(id: String,shapes: Array,layer: int,mask: int) -> void:
	if shapes.is_empty():
		var empty:=SphereShape3D.new(); empty.radius=.0001; add(id,empty,Transform3D.IDENTITY,0,0); return
	add(id,shapes[0].shape,shapes[0].offset,layer,mask); bodies[id].compound=shapes
	for i in range(1,shapes.size()): PhysicsServer3D.body_add_shape(bodies[id].rid,shapes[i].shape.get_rid(),shapes[i].offset)
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
	bodies[id].pose=transform; bodies[id].enabled=enabled
	var scale := transform.basis.get_scale().abs().max(Vector3.ONE * .0001)
	PhysicsServer3D.body_set_shape_transform(bodies[id].rid, 0, Transform3D(Basis.from_scale(scale), Vector3.ZERO) * bodies[id].offset)
	if bodies[id].has("compound"):
		for i in bodies[id].compound.size():
			PhysicsServer3D.body_set_shape_transform(bodies[id].rid,i,Transform3D(Basis.from_scale(scale),Vector3.ZERO)*bodies[id].compound[i].offset)
			PhysicsServer3D.body_set_shape_disabled(bodies[id].rid,i,not enabled)
	PhysicsServer3D.body_set_state(bodies[id].rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(transform.basis.orthonormalized(), transform.origin))
	PhysicsServer3D.body_set_shape_disabled(bodies[id].rid, 0, not enabled)
func move(id: String, from: Transform3D, motion: Vector3, exclude: Array[String] = []) -> Dictionary:
	if not bodies.has(id): return {"travel": motion, "hits": []}
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = Transform3D(from.basis.orthonormalized(), from.origin); parameters.motion = motion; parameters.margin = .002; parameters.max_collisions = 4; parameters.recovery_as_collision = true
	# A tiny probe ensures contact detection when an animated collider reaches a
	# stationary gravity-free body. A miss still returns the original zero motion.
	if motion.is_zero_approx(): parameters.motion=Vector3.DOWN*.0001
	# Native array getters return a reconstructed list. Mutating that temporary
	# does not update the server's exclusion set; assign the completed list.
	var excluded_bodies: Array[RID]=[]
	for other in exclude:
		if bodies.has(other): excluded_bodies.append(bodies[other].rid)
	parameters.exclude_bodies=excluded_bodies
	var result := PhysicsTestMotionResult3D.new(); query_count += 1
	if not PhysicsServer3D.body_test_motion(bodies[id].rid, parameters, result): return {"travel": motion, "hits": []}
	var hits := []
	for i in result.get_collision_count():
		hits.append({"normal": result.get_collision_normal(i), "point": result.get_collision_point(i), "depth": result.get_collision_depth(i), "actor": owners.get(result.get_collider_rid(i), "")})
	return {"travel": result.get_travel(), "hits": hits}
func point_motion(id: String, from: Vector3, to: Vector3, radius: float, layer: int, mask: int, exclude: Array[String]) -> Dictionary:
	# Reuse a query shape per mask, not a body per radius (size-varied powder
	# otherwise creates thousands of native probe bodies).
	var probe := "@probe:" + str(mask)
	if not bodies.has(probe):
		var shape := SphereShape3D.new(); shape.radius = maxf(.0001, radius)
		add(probe, shape, Transform3D.IDENTITY, 0, mask)
	elif not is_equal_approx((bodies[probe].shape as SphereShape3D).radius,radius): (bodies[probe].shape as SphereShape3D).radius=maxf(.0001,radius)
	var ignored: Array[String] = exclude.duplicate(); ignored.append(id)
	var result := move(probe, Transform3D(Basis.IDENTITY, from), to - from, ignored)
	if from.is_equal_approx(to) and result.hits.is_empty():
		# Motion sweeps can miss an already-overlapping sphere/cylinder pair.
		# Ask the same offline broadphase for a rest contact, not a fake floor hit.
		var query:=PhysicsShapeQueryParameters3D.new(); query.shape=bodies[probe].shape; query.transform=Transform3D(Basis.IDENTITY,from); query.collision_mask=mask; query.margin=.001
		var excluded_rids: Array[RID]=[bodies[probe].rid]
		for other in ignored:
			if bodies.has(other): excluded_rids.append(bodies[other].rid)
		query.exclude=excluded_rids
		var info:=PhysicsServer3D.space_get_direct_state(space).get_rest_info(query); query_count+=1
		if not info.is_empty():
			var normal: Vector3=info.normal; var depth:=maxf(.001,radius-(from-(info.point as Vector3)).dot(normal))
			result.hits.append({"normal":normal,"point":info.point,"depth":depth,"actor":owners.get(info.rid,"")}); result.travel=normal*minf(depth,radius*2)
	return {"position": from + result.travel, "hits": result.hits}
func _notification(what: int) -> void:
	# Script methods cannot be dispatched on a RefCounted during finalization.
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in bodies.values(): PhysicsServer3D.free_rid(entry.rid)
		if space.is_valid(): PhysicsServer3D.free_rid(space)
