extends RefCounted
## Froxel sampling is renderer-wide, never a fake per-volume quality slider.
const PRESETS:=[Vector2i(64,32),Vector2i(128,64),Vector2i(192,96),Vector2i(256,128)]
const NAMES:=["Fast","Balanced","Detailed","Final render"]
static func apply(values: Dictionary) -> void:
	_native().apply(values)

static func attach(tabs: Node) -> void:
	_native().attach(tabs)

static func assign(project: Project,values: Dictionary) -> void:
	_native().assign(project,values)

static func apply_scene_shadow(tabs: Node) -> void:
	_native().apply_scene_shadow(tabs)

static func edit(tabs: Node,values: Dictionary) -> void:
	_native().edit(tabs,values)

static func show_menu(button: Button,tabs: Node) -> void:
	_native().show_menu(button,tabs)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_render_settings")
