#ATTACH TO ANY DIALOG MENU THAT GIVES PARAMETERS, AND CALL 1 FUNCTION
class_name DialogParamChooser
extends Control

@export var close_button: Button
@export var select_button: Button
@export var mappings: Array[DialogParamChooserMapping]


var _state: Dictionary


func _ready() -> void:
	close_button.pressed.connect(func():
		_state.badboy = true
		)
	
	select_button.pressed.connect(func():
		_state.finished = true
		)


#gets parameters from ui elements and returns their value when select button pressed
#if close button pressed, returns an empty dictionary
func select_params() -> Dictionary:
	visible = true
	
	_state = {
		"finished" = false,
		"badboy" = false
	}
	
	while !_state.finished:
		await get_tree().process_frame
		if _state.badboy: visible = false; return Dictionary()
	
	var dic: Dictionary = {}
	
	for mapping: DialogParamChooserMapping in mappings:
		dic[mapping.tag] = get_node(mapping.node).get(mapping.property_name)
	
	visible = false
	return dic
