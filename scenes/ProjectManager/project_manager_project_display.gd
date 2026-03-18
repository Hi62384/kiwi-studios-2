extends Panel

@onready var texture_rect: TextureRect = $HBoxContainer/TextureRect
@onready var project_name: Label = $HBoxContainer/VBoxContainer/ProjectName
@onready var project_path: Label = $HBoxContainer/VBoxContainer/ProjectPath
@onready var button: Button = $Button
@onready var selected_cover: ColorRect = $SelectedCover
@onready var error_cover: ColorRect = $ErrorCover
