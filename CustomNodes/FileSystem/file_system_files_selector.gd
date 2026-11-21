extends Node

const ExpandableButton = preload("res://scripts/Extra/ExpandableButtonControl.cs")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."


var _selected_expandable_buttons: Array[ExpandableButton]



func _ready() -> void:
	_native_selection().ready(self)

func clear_selected() -> void:
	_native_selection().clear_selected(self)

func get_selected_expandable_buttons() -> Array[ExpandableButton]:
	return _native_selection().get_selected_expandable_buttons(self)

func get_expandable_buttons_top_selected_files() -> Array[ExpandableButton]:
	return _native_selection().top_selected_files(self)

func _get_expandable_buttons_between(expandable_button1: ExpandableButton, expandable_button2: ExpandableButton) -> Array[ExpandableButton]:
	return _native_selection().between(self,expandable_button1,expandable_button2)

func _get_top_selected_expandable_button() -> ExpandableButton:
	return _native_selection().extreme(self,true)

func _get_bottom_selected_expandable_button() -> ExpandableButton:
	return _native_selection().extreme(self,false)

func _get_expandable_button_to_shift_connect_to(expandable_button: ExpandableButton) -> ExpandableButton:
	return _native_selection().shift_anchor(self,expandable_button)

func _toggle_select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	_native_selection().toggle(self,expandable_buttons)

func expandable_button_is_selected(expandable_button: ExpandableButton) -> bool:
	return _native_selection().is_selected(self,expandable_button)

func _deselect_all_expandable_buttons() -> void:
	_native_selection().deselect_all(self)

func _deselect_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	_native_selection().deselect(self,expandable_buttons)

func _select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	_native_selection().select(self,expandable_buttons)

func handle_input_for_right_clicked_file(expandable_button: ExpandableButton) -> void:
	_native_selection().right_clicked(self,expandable_button)

func handle_input_for_clicked_file(expandable_button: ExpandableButton) -> void:
	_native_selection().clicked(self,expandable_button)


static func _native_selection() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("project_file_selection")
