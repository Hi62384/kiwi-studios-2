extends ActorRuntime
## Minimal spatial actor. Add meshes, cameras, etc. beneath Transform as needed.

@onready var transform_node: Node3D = $Transform
var parenting_anchor: Node3D


func _ready() -> void:
	parenting_anchor = Node3D.new()
	parenting_anchor.name = "ParentingAnchor"
	add_child(parenting_anchor)


func set_active(value: bool) -> void:
	super.set_active(value)
	transform_node.visible = value


func parenting_node() -> Node:
	return parenting_anchor if parenting_anchor != null else self


func evaluate_transform(values: Dictionary) -> void:
	var position: Vector3 = values.get(&"position", Vector3.ZERO)
	var rotation: Vector3 = values.get(&"rotation", Vector3.ZERO)
	var actor_scale: Vector3 = values.get(&"scale", Vector3.ONE)
	transform_node.position = position
	transform_node.rotation_degrees = rotation
	transform_node.scale = actor_scale
	parenting_anchor.position = position
	parenting_anchor.rotation_degrees = rotation
	parenting_anchor.scale = actor_scale
	if values.has(&"model_basis_residual"):
		var exact: Basis=Basis.from_euler(transform_node.rotation)*Basis.from_scale(actor_scale)*values[&"model_basis_residual"]
		transform_node.basis=exact; parenting_anchor.basis=exact


func evaluate(_local_time: float, _values: Dictionary) -> void:
	pass


func supports_remote_transform() -> bool:
	return true


func remote_transform() -> Transform3D:
	return transform_node.global_transform


func apply_remote_transform(source: Transform3D, use_position: bool, use_rotation: bool, use_scale: bool) -> void:
	var result := transform_node.global_transform
	if use_position:
		result.origin = source.origin
	var rotation := source.basis.get_rotation_quaternion() if use_rotation else result.basis.get_rotation_quaternion()
	var actor_scale := source.basis.get_scale() if use_scale else result.basis.get_scale()
	result.basis = Basis(rotation) * Basis.from_scale(actor_scale)
	transform_node.global_transform = result
	parenting_anchor.global_transform = result
