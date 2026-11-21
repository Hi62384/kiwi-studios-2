class_name KiwiModelWorkspace
extends Control
const Selection = preload("res://Workspaces/ModelWorkspace/KiwiModelSelection.cs")
signal document_changed
signal model_saved(path: String, saved_session: KiwiModelSession)
signal use_in_scene(path: String)
var session := KiwiModelSession.new()
var canvas := KiwiModelViewport.new()
var path := ""
var source: Variant
var title := Label.new()
var status := Label.new()
var hierarchy: Tree=preload("res://Workspaces/ModelWorkspace/ModelHierarchy.cs").new()
var properties := VBoxContainer.new()
var context := HBoxContainer.new()
var mode_buttons: Dictionary = {}
var _refresh_pending := false
var _property_gesture := false
var _syncing := false
var _last_geometry := "Extrude"
var _last_amount := .2
var _recent: Array[String] = []
var _inspector_tabs := TabContainer.new()
var _modifiers := VBoxContainer.new()
var _surfaces := VBoxContainer.new()
var _main_split: HSplitContainer
var _left_split: HSplitContainer
var _transform_fields: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _snap_button: CheckButton
var _space_picker: OptionButton
var _layout_ready := false
var _pending_panels: Dictionary = {}
var rig_ui: KiwiRigUI
const OPERATIONS := ["Extrude","Extrude individual","Inset","Bevel","Subdivide","Weld","Smooth","Flip normals","Separate faces","Join meshes","Duplicate","Delete","Group","Parent","Unparent","Center origin","Select all","Invert selection","Select connected","Grow selection","Shrink selection","Select similar normals","Select material","Frame selected","Frame all","Boolean difference","Boolean union","Boolean intersection","Repeat operation"]

func _ready() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("setup",self)

func _initial_layout() -> void:
	await get_tree().process_frame
	if is_inside_tree(): Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("initial_layout",self)

func _capture_panels() -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("capture_panels",self)

func _restore_panels(state: Dictionary) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("restore_panels",self,state)

func _draw() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("draw",self)

func _build_theme() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("build_theme",self)

func _button(parent: Node, label: String, action: Callable, tooltip: String="") -> Button:
	var bridge:=ChoiceCallback.new(); bridge.callback=action
	return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("button",parent,label,bridge,tooltip)

func _separator(parent: Node) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("separator",parent)

func _label(parent: Node, text: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("label",parent,text)

func _clear(parent: Node) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("clear",parent)

func _changed() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("changed",self)

func _process(_delta: float) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("process",self)

func _refresh() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("refresh",self)

func _sync_transform_fields() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("sync_transform_fields",self)

func _number(parent: Node, label: String, value: float, minimum: float, maximum: float, step: float, setter: Callable) -> DragNumber:
	var bridge:=ChoiceCallback.new(); bridge.callback=setter
	return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("number",self,parent,label,value,minimum,maximum,step,bridge)

func _transform_value(value: float, kind: String, axis: int) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("transform_value",self,value,kind,axis)

func _parameter_value(value: float, id: String, field: String, dimensions: bool) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("parameter_value",self,value,id,field,dimensions)

func _rebuild_tree() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("rebuild_tree",self)

func _tree_input(event: InputEvent) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("tree_input",self,event)

func _tree_button(row: TreeItem, _column: int, _id: int, _mouse_button: int) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("tree_button",self,row)

func _tree_selected(_row: TreeItem, _column: int, _selected: bool) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("tree_selected",self,_row,_column,_selected)

func _rename() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("rename",self)

func _build_modifiers(item: KiwiModelComponent) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("build_modifiers",self,item)

func _build_surfaces(item: KiwiModelComponent) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("build_surfaces",self,item)

func _load_material() -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("load_material",self)

func create_menu() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("create_menu",self)

func _deform_menu() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("deform_menu",self)

class ChoiceCallback:
	extends RefCounted
	var callback: Callable
	func invoke(value: Variant) -> void: callback.call(value)
	func invoke_no_args() -> void: callback.call()
	func release() -> void: callback=Callable()
func _command_choices() -> Dictionary: return {"operations":OPERATIONS,"shapes":KiwiModelPrimitives.SHAPES,"modifiers":KiwiModelModifiers.TYPES}
func _choice_menu(heading: String, choices: Array, chosen: Callable) -> void:
	var bridge:=ChoiceCallback.new(); bridge.callback=chosen
	Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("choice_menu",self,heading,choices,bridge)
static func _matches(query: String, label: String) -> bool: return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("matches",query,label)

func command_search() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("command_search",self)

func run_command(command: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("run_command",self,command)

func _operation_dialog(kind: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("operation_dialog",self,kind)

func _selection(command: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("selection",self,command)

func _separate() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("separate",self)

func _center_origin() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("center_origin",self)

func _boolean(command: String) -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("boolean",self,command)

func _view_command(index: int) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("view_command",self,index)

func open_source(value: Variant, state: Dictionary={}) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("open_source",self,value,state)

func capture_state() -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("capture_state",self)

func _exit_tree() -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("exit_tree",self)

func _rig_state() -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("rig_state",self)

func _to_scene_after_save() -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("to_scene_after_save",self)

func open_dialog() -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("open_dialog",self)

func save() -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("save",self)

func save_as() -> void:
	await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("save_as",self)

func save_to(destination: String) -> Error:
	return await Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("save_to",self,destination)

func _unhandled_key_input(event: InputEvent) -> void: Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("key_input",self,event)
