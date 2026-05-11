@tool
extends Button

@onready var icon_texture_rect: TextureRect = $HBoxContainer/TextureRect
@onready var text_label: Label = $HBoxContainer/Label
@onready var more_options_button: Button = $HBoxContainer/Button
@onready var key_shortcut: Label = $key_shortcut

@export var panel_icon: Texture2D:
	set(v):
		panel_icon = v
		
		if !is_node_ready():
			await ready
		
		icon_texture_rect.texture = panel_icon

@export var panel_text: String:
	set(v):
		panel_text = v
		
		if !is_node_ready():
			await ready
		
		text_label.text = panel_text

@export var key_shortcut_text: String:
	set(v):
		key_shortcut_text = v
		
		if !is_node_ready():
			await ready
		
		key_shortcut.text = key_shortcut_text

@export var has_more_options: bool = false:
	set(v):
		has_more_options = v
		
		if !is_node_ready():
			await ready
		
		more_options_button.visible = has_more_options
