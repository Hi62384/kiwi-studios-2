class_name ActorSceneMenuButton
extends Button

var current_scene_path: String = ""
var menu: PopupPanel
var path_label: Label
var timeline: ActorTimelineEditor
var scene_tabs: ActorSceneTabs


func _ready() -> void:
	_native_scene_menu().ready(self)

func _unhandled_key_input(event: InputEvent) -> void:
	_native_scene_menu().unhandled_key_input(self,event)

func _open_menu() -> void:
	_native_scene_menu().open_menu(self)

func _add_action(parent: VBoxContainer, title: String, shortcut: String, subtitle: String, action: Callable) -> void:
	_native_scene_menu().add_action(self,parent,title,shortcut,subtitle,action)

func _save() -> void:
	var path: String=_native_scene_menu().active_path(self)
	if path.is_empty(): await _save_as()
	else: _write_scene(path)

func _save_as() -> void:
	if timeline==null: return
	var suggested: String=_native_scene_menu().suggested_name(self)
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save editable scene",suggested,"tres",false,PackedStringArray(),_capture_scene)
	if not result.get("cancelled",true) and not str(result.get("path","")).is_empty(): _write_scene(str(result.path))

func _write_scene(path: String) -> void:
	_native_scene_menu().write_scene(self,path)

func _load() -> void:
	if timeline==null: return
	var property: ActorProperty=_native_scene_menu().picker_property()
	var path:=await ActorProjectFilePicker.pick(self,property,"Load editable scene")
	_native_scene_menu().load_scene(self,path)

func _instantiate_scene() -> void:
	if timeline==null: return
	var property: ActorProperty=_native_scene_menu().picker_property()
	var path:=await ActorProjectFilePicker.pick(self,property,"Instantiate a scene")
	_native_scene_menu().instantiate_scene(self,path)

func _relative_path(path: String) -> String:
	return _native_scene_menu().relative_path(path)

func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	return _native_scene_menu().box(color,border,radius,width)


func _capture_scene() -> Resource:
	return _native_scene_menu().capture_scene(self)

func _invoke_scene_action(action: Callable) -> void:
	if action.is_valid(): action.call()

static func _native_scene_menu() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("scene_menu")
