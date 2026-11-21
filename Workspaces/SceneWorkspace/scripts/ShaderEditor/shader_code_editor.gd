class_name ShaderCodeEditor
extends PanelContainer
## Lightweight project shader editor. Double-click a .gdshader file to open it.

signal shader_changed(source: Variant)
signal save_shortcut_requested(save_as: bool)

var code := CodeEdit.new()
var title := Label.new()
var diagnostics := Label.new()
var documentation_button := Button.new()
var documentation: ShaderDocumentationPopup
var workspace_picker := OptionButton.new()
var scene_tree := ActorSceneTree.new()
var shader_workspace := VBoxContainer.new()
var current_path: String = ""
var current_shader: Shader
var save_timer := Timer.new()
var _loading := false
var auto_save_enabled := true
## The full shader-tab workspace embeds only the code editor portion of this
## control. The compact scene sidebar keeps the workspace switcher/tree.
var dedicated_mode := false

const COMPLETIONS := [
	"shader_type spatial;", "shader_type canvas_item;", "shader_type fog;", "render_mode", "uniform", "group_uniforms",
	"void vertex()", "void fragment()", "void light()", "void fog()", "float", "int", "bool",
	"vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D", "samplerCube",
	"if", "else", "for", "while", "break", "continue", "return", "discard", "struct", "mix", "clamp", "smoothstep",
	"normalize", "dot", "cross", "reflect", "refract", "texture", "sin", "cos", "pow",
	"VERTEX", "NORMAL", "UV", "COLOR", "ALBEDO", "ALPHA", "ROUGHNESS", "METALLIC",
	"SPECULAR", "EMISSION", "NORMAL_MAP", "NORMAL_MAP_DEPTH", "DENSITY", "WORLD_POSITION",
	"OBJECT_POSITION", "UVW", "SIZE", "SDF", "TIME", "SCREEN_UV"
]

func _ready() -> void:
	_native_editor().ready(self)

func _connect_filesystem() -> void:
	_native_editor().connect_filesystem(self)

func _open_library_sample(entry: Dictionary) -> void:
	_native_editor().open_library_sample(self,entry)

func _connect_timeline() -> void:
	_native_editor().connect_timeline(self)

func _workspace_selected(index: int) -> void:
	_native_editor().workspace_selected(self,index)

func _workspace_switcher_panel() -> StyleBoxFlat:
	return _native_editor().workspace_switcher_panel()

func _style_workspace_picker() -> void:
	_native_editor().style_workspace_picker(self)

func open_shader(source: Variant) -> void:
	_native_editor().open_shader(self,source)

func save() -> void:
	_native_editor().save(self)

func _notify_shader_changed(source: Variant) -> void:
	_native_editor().notify_shader_changed(self,source)

func _text_changed() -> void:
	_native_editor().text_changed(self)

func _validate_syntax() -> void:
	_native_editor().validate_syntax(self)

func _lines_without_comments() -> PackedStringArray:
	return _native_editor().lines_without_comments(self)

func _code_input(event: InputEvent) -> void:
	_native_editor().code_input(self,event)

func _input(event: InputEvent) -> void:
	_native_editor().input(self,event)

func _complete_code() -> void:
	_native_editor().complete_code(self)

func _make_highlighter() -> CodeHighlighter:
	return _native_editor().make_highlighter()


static func _native_editor() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("shader_code_editor")
