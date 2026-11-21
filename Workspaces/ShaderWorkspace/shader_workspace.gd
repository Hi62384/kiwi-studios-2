class_name KiwiShaderWorkspace
extends Control
## Full-document shader authoring workspace used by top-level editor tabs.

signal document_changed
signal shader_saved(source: Variant)

var editor := ShaderCodeEditor.new()
var viewport := SubViewport.new()
var viewport_display := TextureRect.new()
var preview_root := Node3D.new()
var mesh_holder := Node3D.new()
var camera_rig := Node3D.new()
var camera := Camera3D.new()
var environment_node := WorldEnvironment.new()
var preview_shader := Shader.new()
var spatial_material := ShaderMaterial.new()
var sky_material := ShaderMaterial.new()
var canvas_material := ShaderMaterial.new()
var fog_preview_material := ShaderMaterial.new()
var fog_preview := FogVolume.new()
var particle_preview := GPUParticles3D.new()
var particle_material := ShaderMaterial.new()
var fog_preview_guide := MeshInstance3D.new()
var canvas_preview := TextureRect.new()
var canvas_preview_background := TextureRect.new()
var current_source: Variant
var current_path := ""
var shader_kind := "spatial"
var shape_picker := OptionButton.new()
var mesh_label := Label.new()
var mesh_group: VBoxContainer
var environment_group: VBoxContainer
var canvas_image_group: VBoxContainer
var canvas_image_label := Label.new()
var shader_type_label := Label.new()
var save_button: Button
var save_as_button: Button
var load_shader_button: Button
var status := Label.new()
var parameters_panel := PanelContainer.new()
var parameters_list := VBoxContainer.new()
var parameter_code_split := VSplitContainer.new()
var parameter_values: Dictionary = {}
var parameter_link := CheckButton.new()
var linked_parameter_reader: Callable
var linked_parameter_writer: Callable
var parameters_linked := false
var parameter_expanded: Dictionary = {}
var registry := ActorRegistry.new()
var _loading := false
var _looking := false
var _last_mouse := Vector2.ZERO
var _mesh_mode := "shape"
var _mesh_path := ""
var _environment_path := ""
var _canvas_image_path := ""
var requires_path := false
var camera_speed := 3.0
var _studio_panorama_texture: Texture2D

const STUDIO_PANORAMA_PATH := "res://resources/environments/ShaderStudioPanorama.png"


func _shader_native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","shader_workspace")
func _parameter_binding_valid(which: String) -> bool:
	if which=="reader": return linked_parameter_reader.is_valid()
	if which=="writer": return linked_parameter_writer.is_valid()
	return linked_parameter_reader.is_valid() and linked_parameter_writer.is_valid()
func _read_linked_parameters() -> Variant: return linked_parameter_reader.call() if linked_parameter_reader.is_valid() else null
func _write_linked_parameter(name: StringName,value: Variant,mode: String,original: Variant) -> void:
	if linked_parameter_writer.is_valid(): linked_parameter_writer.call(name,value,mode,original)

func _ready() -> void:
	BasicActors.register_all(registry)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_preview()
	visibility_changed.connect(_sync_preview_visibility)
	_sync_preview_visibility()
	set_process(true)


func _build_ui() -> void:
	_shader_native().call("build_ui", self)


func _build_preview() -> void: _shader_native().call("build_preview",self)

func open_source(source: Variant,state: Dictionary={},binding: Dictionary={}) -> void: _shader_native().call("open_source",self,source,state,binding)

func capture_state() -> Dictionary: return _shader_native().call("capture_state",self)

func save() -> void:
	var job: Node=_shader_native().call("save",self)
	if job!=null and not job.finished: await job.completed

func _commit_linked_parameters() -> void: _shader_native().call("commit_linked_parameters",self)

func save_as() -> void:
	var job: Node=_shader_native().call("file_action",self,"save_as",&"",false)
	if not job.finished: await job.completed

func _code_changed() -> void: _shader_native().call("code_changed",self)

func _rebind_preview_materials() -> void: _shader_native().call("rebind_preview_materials",self)

func _preview_parameter_value(value: Variant) -> Variant: return _shader_native().call("preview_parameter_value",value)

func _shader_type(source: String) -> String: return _shader_native().call("shader_type",source)

func _apply_materials() -> void: _shader_native().call("apply_materials",self)

func _update_preview_mode() -> void: _shader_native().call("update_preview_mode",self)

func _sync_preview_visibility() -> void: _shader_native().call("sync_preview_visibility",self)

func _apply_environment() -> void: _shader_native().call("apply_environment",self)

func _studio_panorama() -> Texture2D: return _shader_native().call("studio_panorama",self)

func _rebuild_mesh() -> void: _shader_native().call("rebuild_mesh",self)

func _choose_mesh() -> void:
	var job: Node=_shader_native().call("file_action",self,"mesh",&"",false)
	if not job.finished: await job.completed

func _choose_shader_file() -> void:
	var job: Node=_shader_native().call("file_action",self,"shader",&"",false)
	if not job.finished: await job.completed

func _choose_environment() -> void:
	var job: Node=_shader_native().call("file_action",self,"environment",&"",false)
	if not job.finished: await job.completed

func _choose_canvas_image() -> void:
	var job: Node=_shader_native().call("file_action",self,"canvas",&"",false)
	if not job.finished: await job.completed

func _update_canvas_texture() -> void: _shader_native().call("update_canvas_texture",self)

func _fit_canvas_preview() -> void: _shader_native().call("fit_canvas_preview",self)

func _godot_project_path(path: String) -> String: return _shader_native().call("godot_project_path",path)

func _default_canvas_texture() -> Texture2D: return _shader_native().call("default_canvas_texture",self)

func _build_parameters_section(parent: Control) -> void:
	_shader_native().call("build_parameters_section", self, parent)


func _rebuild_parameters() -> void:
	_shader_native().call("rebuild_parameters", self)


func _add_parameter_row(name: StringName, value_type: int, hint: String) -> void:
	_shader_native().call("add_parameter_row", self, name, value_type, hint)


func _add_texture_parameter(parent: VBoxContainer, name: StringName, value: Variant) -> void:
	_shader_native().call("add_texture_parameter", self, parent, name, value)


func _add_noise_property(parent: VBoxContainer, parameter_name: StringName, noise: ActorObjectData, definition: ActorObjectDefinition, property: ActorProperty, preview: TextureRect) -> void:
	_shader_native().call("add_noise_property", self, parent, parameter_name, noise, definition, property, preview)


func _noise_from_parameter(value: Variant) -> ActorObjectData:
	return _shader_native().call("noise_from_parameter", value)


func _set_parameter_image_path(name: StringName, path: String) -> void:
	_shader_native().call("set_parameter_image_path", self, name, path)


func _shader_uniform_default(name: StringName,value_type: int) -> Variant: return _shader_native().call("shader_uniform_default",self,name,value_type)

func _declared_uniform_default(name: StringName,value_type: int) -> Dictionary: return _shader_native().call("declared_uniform_default",editor.code.text,name,value_type)

func _add_parameter_number(parent: Control, name: StringName, value: float, value_type: int, hint: String) -> void:
	_shader_native().call("add_parameter_number", self, parent, name, value, value_type, hint)


func _hint_range(hint: String) -> PackedFloat32Array: return _shader_native().call("hint_range",hint)

func _vector_parameter_changed(next: float,name: StringName,component: int,value_type: int,mode: String="edit",original: Variant=null) -> void: _shader_native().call("vector_parameter_changed",self,next,name,component,value_type,mode,original)

func _set_preview_parameter(name: StringName,value: Variant,mode: String="edit",original: Variant=null) -> void: _shader_native().call("set_preview_parameter",self,name,value,mode,original)

func _reset_preview_parameter(name: StringName) -> void: _shader_native().call("reset_preview_parameter",self,name)

func _uniform_type(name: StringName) -> int: return _shader_native().call("uniform_type",self,name)

func _current_parameter_values() -> Dictionary: return _shader_native().call("current_parameter_values",self)

func _parameter_link_toggled(enabled: bool) -> void: _shader_native().call("parameter_link_toggled",self,enabled)

func _reset_all_preview_parameters() -> void: _shader_native().call("reset_all_preview_parameters",self)

func _style_parameter_color(button: ColorPickerButton,value: Color) -> void: _shader_native().call("style_parameter_color",button,value)

func _choose_parameter_texture(name: StringName,from_clipboard: bool=false) -> void:
	var job: Node=_shader_native().call("file_action",self,"parameter",name,from_clipboard)
	if not job.finished: await job.completed

func _viewport_input(event: InputEvent) -> void: _shader_native().call("viewport_input",self,event)

func _unhandled_key_input(event: InputEvent) -> void: _shader_native().call("unhandled_key_input",self,event)

func _process(delta: float) -> void: _shader_native().call("process",self,delta)

func _viewport_help() -> String: return _shader_native().call("viewport_help",self)

func _document_title() -> String: return _shader_native().call("document_title",self)

func _button(text: String,accent: bool) -> Button: return _shader_native().call("button",text,accent)

func _box(background: Color,border: Color,radius: int) -> StyleBoxFlat: return _shader_native().call("box",background,border,radius)


func _clipboard_action(id: int) -> void:
	if id == 0:
		var shader := Shader.new()
		shader.code = editor.code.text
		KiwiSuperClipboardService.instance.quick_save(shader, _document_title())
	else:
		KiwiSuperClipboardService.instance.toggle()

func _copy_parameter_to_clipboard(name: StringName) -> void:
	KiwiSuperClipboardService.instance.quick_save(parameter_values.get(name), str(name))
