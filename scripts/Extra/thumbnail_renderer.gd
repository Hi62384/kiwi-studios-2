extends Node3D

const ThumbnailRenderer = preload("uid://g3isy00e4xs5")
const DEFAULT_ENVIRONMENT = preload("uid://bngpc7xkudi0e")

@onready var object_holder: MeshInstance3D = $SubViewport/ObjectHolder
@onready var sphere_renderer: MeshInstance3D = $SubViewport/SphereRenderer
@onready var camera_3d: Camera3D = $SubViewport/Camera3D
@onready var directional_light_3d: DirectionalLight3D = $SubViewport/DirectionalLight3D
@onready var sub_viewport: SubViewport = $SubViewport

static var _instance: ThumbnailRenderer
static var _render_busy := false

static func _begin_render() -> void:
	while _render_busy:
		await _instance.get_tree().process_frame
	_render_busy = true


enum RenderTargets {
	OBJECT,
	MATERIAL,
	WORLD
}


func _ready() -> void:
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null
		_render_busy = false



static func _delete_objects() -> void:
	for a in _instance.object_holder.get_children():
		a.queue_free()



static func _set_target_visibility(target: RenderTargets) -> void:
	_delete_objects()
	_instance.object_holder.mesh = null
	_instance.sub_viewport.find_world_3d().environment = DEFAULT_ENVIRONMENT
	
	_instance.object_holder.visible = target == RenderTargets.OBJECT
	_instance.sphere_renderer.visible = target == RenderTargets.MATERIAL
	_instance.sub_viewport.transparent_bg = target != RenderTargets.WORLD



static func _center_object_holder() -> void:
	var aabb: AABB = _instance.object_holder.get_aabb()
	var center_local = aabb.position + aabb.size * 0.5
	var center_global = _instance.object_holder.to_global(center_local)
	var distance = 5.0
	var target_pos = _instance.camera_3d.global_transform.origin - _instance.camera_3d.global_transform.basis.z * distance

	# Offset needed to bring AABB center to target
	var offset = target_pos - center_global

	_instance.object_holder.global_position += offset



static func _snap_photo() -> Texture2D:
	_instance.sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if DisplayServer.get_name() == "headless":
		await _instance.get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	var image := _instance.sub_viewport.get_texture().get_image()
	_render_busy = false
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null



static func render_material(material: StandardMaterial3D) -> Texture2D:
	await _begin_render()
	_set_target_visibility(RenderTargets.MATERIAL)
	_instance.sphere_renderer.material_override = material
	return await _snap_photo()



static func render_mesh(mesh: Mesh) -> Texture2D:
	await _begin_render()
	_set_target_visibility(RenderTargets.OBJECT)
	_instance.object_holder.mesh = mesh
	_center_object_holder()
	return await _snap_photo()



static func render_scene(scene: PackedScene) -> Texture2D:
	await _begin_render()
	_set_target_visibility(RenderTargets.OBJECT)
	_instance.object_holder.add_child(scene.instantiate())
	_center_object_holder()
	return await _snap_photo()



static func render_environment(environment: Environment) -> Texture2D:
	await _begin_render()
	_set_target_visibility(RenderTargets.WORLD)
	_instance.sub_viewport.find_world_3d().environment = environment
	return await _snap_photo()


static func render_actor_environment(object: ActorObjectData) -> Texture2D:
	var runtime: Node = load("res://scripts/actors/examples/basic_actor.tscn").instantiate()
	var environment := Environment.new()
	runtime.call("_configure_environment", environment, object)
	runtime.free()
	return await render_environment(environment)
