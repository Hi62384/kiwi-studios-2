@tool
extends VBoxContainer

const POINTER_DOWN = preload("uid://ciadauk2mpudq")
const POINTER_RIGHT = preload("uid://bdblvy7bf8xgn")

@onready var _expandable_icon_button: Button = $Panel/HBoxContainer/ExpandableIconButton
@onready var _expandable_icon: TextureRect = $Panel/HBoxContainer/ExpandableIconButton/ExpandableIcon
@onready var _main_icon: TextureRect = $Panel/HBoxContainer/MainIcon
@onready var _label: Label = $Panel/HBoxContainer/Text
@onready var _children_container: VBoxContainer = $HBoxContainer/ChildrenContainer
@onready var _panel: Panel = $Panel
@onready var _main_button: Button = $Panel/MainButton
@onready var _cover_color_rect: ColorRect = $Panel/CoverColorRect

@export var expanded: bool = false:
	set(v):
		expanded = v
		
		if !is_node_ready(): return
		
		_expandable_icon.texture = POINTER_DOWN if expanded else POINTER_RIGHT
		_children_container.visible = expanded
		toggled.emit(v)
	

@export_group("icon")

@export var icon: Texture2D:
	set(v):
		icon = v
		
		if !is_node_ready(): return
		
		_main_icon.texture = v

@export_group("Text")

@export var text: String = "":
	set(v):
		text = v
		if !is_node_ready(): return
		_label.text = v

@export var label_settings: LabelSettings:
	set(v):
		label_settings = v
		if !is_node_ready(): return
		_label.label_settings = label_settings

@export_group("style")

@export var panel_stylebox: StyleBox:
	set(v):
		panel_stylebox = v
		if !is_node_ready(): return
		_panel.add_theme_stylebox_override("panel", v)

@export var cover_colorrect_color: Color = Color(1,1,1,0.05):
	set(v):
		cover_colorrect_color = v
		if !is_node_ready(): return
		_cover_color_rect.color = v


signal toggled(on: bool)



func _ready() -> void:
	_expandable_icon_button.pressed.connect(func():
		expanded = !expanded
		)


func get_cover_color_rect() -> ColorRect:
	return _cover_color_rect


func get_main_button() -> Button:
	return _main_button


func get_expandable_icon_button() -> Button:
	return _expandable_icon_button


func add_child_in_expand(child: Node) -> void:
	_children_container.add_child(child)
