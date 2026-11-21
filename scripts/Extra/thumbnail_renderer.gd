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

enum RenderTargets { OBJECT, MATERIAL, WORLD }

static func _begin_render() -> bool:
	while true:
		var owner: Node3D=_native_thumbnail().render_owner()
		if owner==null: return false
		if _native_thumbnail().try_begin(): return true
		await owner.get_tree().process_frame
	return false

func _ready() -> void:
	_native_thumbnail().ready(self)

func _exit_tree() -> void:
	_native_thumbnail().exit_tree(self)

static func _delete_objects() -> void:
	_native_thumbnail().delete_objects()

static func _set_target_visibility(target: RenderTargets) -> void:
	_native_thumbnail().set_target_visibility(target)

static func _center_object_holder() -> void:
	_native_thumbnail().center_object_holder()

static func _snap_photo() -> Texture2D:
	var viewport: SubViewport=_native_thumbnail().prepare_snap()
	if viewport==null: return null
	if DisplayServer.get_name()=="headless": await viewport.get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	return _native_thumbnail().finish_snap(viewport,false)

static func render_material(material: StandardMaterial3D) -> Texture2D:
	if not await _begin_render(): return null
	_native_thumbnail().prepare_render("material",material)
	return await _snap_photo()

static func render_mesh(mesh: Mesh) -> Texture2D:
	if not await _begin_render(): return null
	_native_thumbnail().prepare_render("mesh",mesh)
	return await _snap_photo()

static func render_scene(scene: PackedScene) -> Texture2D:
	if not await _begin_render(): return null
	_native_thumbnail().prepare_render("scene",scene)
	return await _snap_photo()

static func render_environment(environment: Environment) -> Texture2D:
	if not await _begin_render(): return null
	_native_thumbnail().prepare_render("environment",environment)
	return await _snap_photo()

static func render_actor_environment(object: ActorObjectData) -> Texture2D:
	var environment: Environment=_native_thumbnail().actor_environment(object)
	return await render_environment(environment)

static func render_text_settings(object: ActorObjectData) -> Texture2D:
	if not await _begin_render(): return null
	var viewport: SubViewport=_native_thumbnail().prepare_text(object)
	if viewport==null: return null
	if DisplayServer.get_name()=="headless": await viewport.get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	return _native_thumbnail().finish_snap(viewport,true)

static func _native_thumbnail() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("thumbnail_renderer")
