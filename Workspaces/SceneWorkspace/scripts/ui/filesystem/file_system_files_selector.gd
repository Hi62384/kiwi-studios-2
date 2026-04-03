extends Node

const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."


var _selected_expandable_buttons: Array[ExpandableButton]



func _ready() -> void:
	LocalProjectFilesystem.node.file_tree_recreated.connect(func():
		_selected_expandable_buttons = []
		)



#if the file/folders parent is selected, dont include the parent/folder. Else, include the parent
func get_expandable_buttons_top_selected_files() -> Array[ExpandableButton]:
	var top_selected_folders: Array[String] = []
	
	#for selected_expandable_button: ExpandableButton in _selected_expandable_buttons:
	#	for expandable_button_to_check: ExpandableButton in _selected_expandable_buttons:
			
	#	pass
	
	return []



func _get_expandable_buttons_between(expandable_button1: ExpandableButton, expandable_button2: ExpandableButton) -> Array[ExpandableButton]:
	var index_button1: int = file_system._ordered_expandable_buttons.find(expandable_button1)
	var index_button2: int = file_system._ordered_expandable_buttons.find(expandable_button2)
	
	var between_buttons: Array[ExpandableButton] = []
	
	if index_button1 > index_button2:
		var temp: int = index_button1
		index_button1 = index_button2
		index_button2 = temp
	
	for i in range(index_button1, index_button2 + 1):
		between_buttons.append(file_system._ordered_expandable_buttons[i])
	
	return between_buttons



func _get_top_selected_expandable_button() -> ExpandableButton:
	var top_button: ExpandableButton
	var highest: int = 999999
	for selected_expandable_button: ExpandableButton in _selected_expandable_buttons:
		var selected_expandable_index_height: int = file_system._ordered_expandable_buttons.find(selected_expandable_button)
		if selected_expandable_index_height < highest:
			highest = selected_expandable_index_height
			top_button = selected_expandable_button
	
	return top_button



func _get_bottom_selected_expandable_button() -> ExpandableButton:
	var bottom_button: ExpandableButton
	var lowest: int = -1
	for selected_expandable_button: ExpandableButton in _selected_expandable_buttons:
		var selected_expandable_index_height: int = file_system._ordered_expandable_buttons.find(selected_expandable_button)
		if selected_expandable_index_height > lowest:
			lowest = selected_expandable_index_height
			bottom_button = selected_expandable_button
	
	return bottom_button



func _get_expandable_button_to_shift_connect_to(expandable_button: ExpandableButton) -> ExpandableButton:
	var top_selected_expandable_button: ExpandableButton = _get_top_selected_expandable_button()
	var bottom_selected_expandable_button: ExpandableButton = _get_bottom_selected_expandable_button()
	
	#only null if currently no expandable buttons are selected
	if top_selected_expandable_button == null or bottom_selected_expandable_button == null:
		return null
	
	var top_selected_expandable_button_index: int = file_system._ordered_expandable_buttons.find(top_selected_expandable_button)
	var bottom_selected_expandable_button_index: int = file_system._ordered_expandable_buttons.find(bottom_selected_expandable_button)
	var reference_expandable_button_index: int = file_system._ordered_expandable_buttons.find(expandable_button)
	
	if reference_expandable_button_index > top_selected_expandable_button_index and reference_expandable_button_index > bottom_selected_expandable_button_index:
		return top_selected_expandable_button
	elif reference_expandable_button_index < top_selected_expandable_button_index and reference_expandable_button_index < bottom_selected_expandable_button_index:
		return bottom_selected_expandable_button
	
	var distance_to_bottom: int = abs(reference_expandable_button_index - bottom_selected_expandable_button_index)
	var distance_to_top: int = abs(reference_expandable_button_index - top_selected_expandable_button_index)
	
	if distance_to_bottom <= distance_to_top:
		return bottom_selected_expandable_button
	return top_selected_expandable_button



func _toggle_select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for expandable_button: ExpandableButton in expandable_buttons:
		if _expandable_button_is_selected(expandable_button):
			_deselect_expandable_buttons([expandable_button])
		else:
			_select_expandable_buttons([expandable_button])



func _expandable_button_is_selected(expandable_button: ExpandableButton) -> bool:
	return _selected_expandable_buttons.has(expandable_button)


func _deselect_all_expandable_buttons() -> void:
	_deselect_expandable_buttons(_selected_expandable_buttons)


func _deselect_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for i: int in expandable_buttons.size():
		var expandable_button: ExpandableButton = expandable_buttons[0]
		expandable_button.get_cover_color_rect().visible = false
		_selected_expandable_buttons.erase(expandable_button)


func _select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for expandable_button: ExpandableButton in expandable_buttons:
		expandable_button.get_cover_color_rect().visible = true
		_selected_expandable_buttons.append(expandable_button)


func handle_input_for_clicked_file(expandable_button: ExpandableButton) -> void:
	if Input.is_action_pressed("ctrl"):
		_toggle_select_expandable_buttons([expandable_button])
	elif Input.is_action_pressed("shift"):
		var expandable_button_to_connect_to: ExpandableButton = _get_expandable_button_to_shift_connect_to(expandable_button)
		_deselect_all_expandable_buttons()
		var buttons_to_select = _get_expandable_buttons_between(expandable_button, expandable_button_to_connect_to)
		_select_expandable_buttons(buttons_to_select)
	else:
		_deselect_all_expandable_buttons()
		_select_expandable_buttons([expandable_button])
