extends ActorRuntime
## A video is a 1m quad with aspect-correct geometry, transformed like other actors.
var mesh: MeshInstance3D
var anchor: Node3D
var material: StandardMaterial3D
var _last_texture: Texture2D
var _time := 0.0
var _values: Dictionary = {}
var _path := ""

func _process(_delta: float) -> void:
	if mesh != null and mesh.visible and not _values.is_empty(): evaluate(_time, _values)

func _ready() -> void:
	mesh = MeshInstance3D.new()
	mesh.layers = 1
	mesh.mesh = QuadMesh.new()
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)
	anchor = Node3D.new()
	add_child(anchor)

func parenting_node() -> Node: return anchor if anchor != null else self

func set_active(value: bool) -> void:
	super.set_active(value)
	if mesh != null: mesh.visible = value

func evaluate_transform(values: Dictionary) -> void:
	if mesh == null: return
	for node in [mesh, anchor]:
		node.position = values.get(&"position", Vector3.ZERO)
		node.rotation_degrees = values.get(&"rotation", Vector3.ZERO)
		node.scale = values.get(&"scale", Vector3.ONE)

func evaluate(time: float, values: Dictionary) -> void:
	_time = time
	_values = values
	if mesh == null: return
	var path := str(values.get(&"video", ""))
	if path != _path:
		_path = path
		material.albedo_texture = null
	var source := ActorVideo.info(path)
	if source.is_empty(): material.albedo_texture = null; return
	var longest := float(maxi(source.width, source.height))
	(mesh.mesh as QuadMesh).size = Vector2(source.width, source.height) / longest
	var texture := ActorVideo.frame(path, time, true)
	if texture != null:
		material.albedo_texture = texture
		_last_texture = texture
