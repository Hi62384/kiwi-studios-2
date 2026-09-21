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
	custom_minimum_size = Vector2(210, 120)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var workspace_bar := PanelContainer.new()
	workspace_bar.name = "WorkspaceSwitcher"
	workspace_bar.add_theme_stylebox_override("panel", _workspace_switcher_panel())
	root.add_child(workspace_bar)
	var workspace_row := HBoxContainer.new()
	workspace_row.add_theme_constant_override("separation", 8)
	workspace_bar.add_child(workspace_row)
	var workspace_mark := Label.new()
	workspace_mark.text = "WORKSPACE"
	workspace_mark.tooltip_text = "Editor workspace"
	workspace_mark.add_theme_color_override("font_color", Color("65d6bb"))
	workspace_mark.add_theme_font_size_override("font_size", 9)
	workspace_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	workspace_row.add_child(workspace_mark)
	workspace_picker.name = "EditorWorkspacePicker"
	workspace_picker.add_item("Scene Tree", 0)
	workspace_picker.add_item("Shader Editor", 1)
	workspace_picker.select(0)
	workspace_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_picker.custom_minimum_size = Vector2(150, 34)
	workspace_picker.tooltip_text = "Choose the editor shown above the Project Filesystem"
	workspace_row.add_child(workspace_picker)
	_style_workspace_picker()
	workspace_picker.item_selected.connect(_workspace_selected)
	scene_tree.name = "ActorSceneTree"
	root.add_child(scene_tree)
	shader_workspace.name = "ShaderWorkspace"
	shader_workspace.add_theme_constant_override("separation", 4)
	shader_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shader_workspace.visible = false
	root.add_child(shader_workspace)
	var header := HBoxContainer.new()
	shader_workspace.add_child(header)
	title.text = "SHADER EDITOR"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 13)
	header.add_child(title)
	documentation_button.name = "ShaderDocumentationButton"
	documentation_button.text = "◇  Shader docs"
	documentation_button.custom_minimum_size = Vector2(138, 32)
	documentation_button.tooltip_text = "Open shader concepts, reference, and copyable examples"
	documentation_button.add_theme_color_override("font_color", Color("9ce8d5"))
	var docs_normal := StyleBoxFlat.new()
	docs_normal.bg_color = Color("172b35")
	docs_normal.border_color = Color("365766")
	docs_normal.set_border_width_all(1)
	docs_normal.set_corner_radius_all(7)
	docs_normal.content_margin_left = 10
	docs_normal.content_margin_right = 10
	var docs_hover := docs_normal.duplicate() as StyleBoxFlat
	docs_hover.bg_color = Color("20413f")
	docs_hover.border_color = Color("62e6c7")
	documentation_button.add_theme_stylebox_override("normal", docs_normal)
	documentation_button.add_theme_stylebox_override("hover", docs_hover)
	documentation_button.add_theme_stylebox_override("pressed", docs_hover)
	header.add_child(documentation_button)
	documentation = ShaderDocumentationPopup.new()
	add_child(documentation)
	documentation_button.pressed.connect(documentation.open)
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true
	code.highlight_current_line = true
	code.auto_brace_completion_enabled = true
	code.indent_automatic = true
	code.indent_size = 4
	code.code_completion_enabled = true
	code.placeholder_text = "Double-click a .gdshader file in the Project Filesystem."
	code.text_changed.connect(_text_changed)
	code.code_completion_requested.connect(_complete_code)
	code.gui_input.connect(_code_input)
	code.focus_entered.connect(func(): FocusableKeyInput.current_focused_instance = null)
	code.syntax_highlighter = _make_highlighter()
	shader_workspace.add_child(code)
	diagnostics.visible = false
	diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostics.add_theme_font_size_override("font_size", 11)
	diagnostics.add_theme_color_override("font_color", Color("ff8f88"))
	shader_workspace.add_child(diagnostics)
	save_timer.one_shot = true
	save_timer.wait_time = 0.25
	save_timer.timeout.connect(save)
	add_child(save_timer)
	add_to_group("shader_code_editor")
	call_deferred("_connect_filesystem")
	if dedicated_mode:
		workspace_bar.visible = false
		workspace_picker.visible = false
		scene_tree.visible = false
		shader_workspace.visible = true
	else:
		call_deferred("_connect_timeline")


func _connect_filesystem() -> void:
	# With document tabs present, filesystem double-clicks belong to the full
	# shader workspace. Shader slots can still open this compact editor directly.
	if get_tree().get_first_node_in_group("actor_scene_tabs") != null:
		return
	var filesystem := get_parent().get_node_or_null("FileSystem")
	if filesystem != null and filesystem.has_signal("shader_file_opened"):
		filesystem.shader_file_opened.connect(open_shader)


func _connect_timeline() -> void:
	var timeline := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
	if timeline != null:
		scene_tree.setup(timeline.model, timeline.registry)


func _workspace_selected(index: int) -> void:
	workspace_picker.select(index)
	scene_tree.visible = index == 0
	shader_workspace.visible = index == 1
	if index == 1:
		code.grab_focus()


func _workspace_switcher_panel() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("121d27")
	panel.border_color = Color("344c60")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(9)
	panel.content_margin_left = 9
	panel.content_margin_right = 7
	panel.content_margin_top = 6
	panel.content_margin_bottom = 6
	return panel


func _style_workspace_picker() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("192a37")
	normal.border_color = Color("3d5b70")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("223c48")
	hover.border_color = Color("5aa58f")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("244c4b")
	pressed.border_color = Color("70d8bd")
	workspace_picker.add_theme_stylebox_override("normal", normal)
	workspace_picker.add_theme_stylebox_override("hover", hover)
	workspace_picker.add_theme_stylebox_override("pressed", pressed)
	workspace_picker.add_theme_stylebox_override("focus", pressed)
	workspace_picker.add_theme_color_override("font_color", Color("e0edf3"))
	workspace_picker.add_theme_color_override("font_hover_color", Color.WHITE)
	workspace_picker.add_theme_color_override("font_pressed_color", Color.WHITE)
	workspace_picker.add_theme_font_size_override("font_size", 13)
	var popup := workspace_picker.get_popup()
	popup.min_size = Vector2i(225, 0)
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = Color("111b25")
	popup_panel.border_color = Color("456176")
	popup_panel.set_border_width_all(1)
	popup_panel.set_corner_radius_all(9)
	popup_panel.shadow_color = Color(0, 0, 0, 0.45)
	popup_panel.shadow_size = 9
	popup_panel.content_margin_left = 7
	popup_panel.content_margin_right = 7
	popup_panel.content_margin_top = 7
	popup_panel.content_margin_bottom = 7
	popup.add_theme_stylebox_override("panel", popup_panel)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color("28534f")
	popup_hover.border_color = Color("67cdb4")
	popup_hover.set_border_width_all(1)
	popup_hover.set_corner_radius_all(6)
	popup.add_theme_stylebox_override("hover", popup_hover)
	popup.add_theme_color_override("font_color", Color("cbdbe5"))
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	popup.add_theme_constant_override("item_start_padding", 13)
	popup.add_theme_constant_override("item_end_padding", 16)
	popup.add_theme_constant_override("v_separation", 7)
	popup.add_theme_font_size_override("font_size", 13)


func open_shader(source: Variant) -> void:
	_workspace_selected(1)
	if not save_timer.is_stopped():
		save()
	save_timer.stop()
	_loading = true
	if source is Shader:
		current_shader = source
		current_path = ""
		code.text = current_shader.code
		title.text = current_shader.resource_name if not current_shader.resource_name.is_empty() else "Embedded Shader"
	else:
		var path := str(source)
		if path.get_extension().to_lower() != "gdshader" or not FileAccess.file_exists(path):
			_loading = false
			return
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_loading = false
			return
		current_path = path
		current_shader = null
		code.text = file.get_as_text()
		title.text = path.get_file()
	_loading = false
	_validate_syntax()
	code.grab_focus()


func save() -> void:
	if current_shader != null:
		current_shader.code = code.text
		current_shader.emit_changed()
		_notify_shader_changed(current_shader)
		return
	if current_path.is_empty():
		return
	var file := FileAccess.open(current_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(code.text)
	# On Windows the write handle must be flushed and closed before any runtime
	# tries to reload this path. Otherwise the immediate refresh can read/cache
	# the previous failed shader; a later uniform edit appears to "fix" it only
	# because the handle has finally closed by then.
	file.flush()
	file.close()
	# Refresh the cached Shader instance so materials in the viewport update too.
	ResourceLoader.load(current_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_notify_shader_changed(current_path)


func _notify_shader_changed(source: Variant) -> void:
	shader_changed.emit(source)
	# This is the same model/runtime evaluation path used by a shader-uniform
	# property edit in ActorInspector.
	get_tree().call_group("actor_timeline_editors", "refresh_saved_shader", source)
	# Runtime nodes can live inside a SubViewport and must not depend on the
	# inspector being open or the timeline having connected this editor signal.
	# Broadcast the saved revision straight to every live shader consumer.
	get_tree().call_group("actor_shader_runtimes", "refresh_saved_shader", source)


func _text_changed() -> void:
	if _loading or (current_path.is_empty() and current_shader == null):
		return
	code.request_code_completion(true)
	_validate_syntax()
	if auto_save_enabled: save_timer.start()


func _validate_syntax() -> void:
	for line in code.get_line_count():
		code.set_line_background_color(line, Color.TRANSPARENT)
	var errors: Array[Dictionary] = []
	var source := code.text
	if not RegEx.create_from_string("(?m)^\\s*shader_type\\s+(spatial|canvas_item|particles|sky|fog)\\s*;").search(source):
		errors.append({"line": 0, "message": "Missing or invalid shader_type declaration."})
	var syntax_lines := _lines_without_comments()
	var struct_names := PackedStringArray()
	var struct_regex := RegEx.create_from_string("\\bstruct\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\{")
	for structure in struct_regex.search_all("\n".join(syntax_lines)):
		if not struct_names.has(structure.get_string(1)):
			struct_names.append(structure.get_string(1))
	var type_pattern := "bool|int|uint|float|vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234]|sampler\\w+"
	for struct_name in struct_names:
		type_pattern += "|" + struct_name
	var declaration_regex := RegEx.create_from_string("(?:^|[,(;{}])\\s*(?:uniform\\s+|varying\\s+|const\\s+|in\\s+|out\\s+|inout\\s+)?(?:lowp\\s+|mediump\\s+|highp\\s+)?(?:" + type_pattern + ")\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var declarations: Dictionary = {}
	var shader_builtins := PackedStringArray(["VERTEX", "NORMAL", "TANGENT", "BINORMAL", "POSITION", "UV", "UV2", "COLOR", "POINT_SIZE", "MODEL_MATRIX", "MODELVIEW_MATRIX", "VIEW_MATRIX", "PROJECTION_MATRIX", "INV_VIEW_MATRIX", "INV_PROJECTION_MATRIX", "MODEL_NORMAL_MATRIX", "CAMERA_POSITION_WORLD", "NODE_POSITION_WORLD", "VIEW", "ALBEDO", "ALPHA", "ALPHA_SCISSOR_THRESHOLD", "METALLIC", "SPECULAR", "ROUGHNESS", "RIM", "RIM_TINT", "CLEARCOAT", "CLEARCOAT_GLOSS", "ANISOTROPY", "ANISOTROPY_FLOW", "SSS_STRENGTH", "SSS_TRANSMITTANCE_COLOR", "SSS_TRANSMITTANCE_DEPTH", "SSS_TRANSMITTANCE_BOOST", "BACKLIGHT", "AO", "AO_LIGHT_AFFECT", "EMISSION", "NORMAL_MAP", "NORMAL_MAP_DEPTH", "DEPTH", "TIME", "PI", "TAU", "E"])
	if RegEx.create_from_string("(?m)^\\s*shader_type\\s+fog\\s*;").search(source) != null:
		shader_builtins.append_array(PackedStringArray(["DENSITY", "WORLD_POSITION", "OBJECT_POSITION", "UVW", "SIZE", "SDF"]))
	var declaration_scopes: Array[Dictionary] = [{}]
	var function_regex := RegEx.create_from_string("^\\s*(?:void|" + type_pattern + ")\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	for line_index in syntax_lines.size():
		var semantic_line := syntax_lines[line_index]
		var trimmed_left := semantic_line.lstrip(" \t")
		var leading_closes := 0
		while leading_closes < trimmed_left.length() and trimmed_left.substr(leading_closes, 1) == "}":
			if declaration_scopes.size() > 1:
				declaration_scopes.pop_back()
			leading_closes += 1
		var function_match := function_regex.search(semantic_line)
		var is_function_signature := function_match != null
		var is_struct_signature := struct_regex.search(semantic_line) != null
		if is_function_signature or is_struct_signature:
			declaration_scopes.append({})
		for declaration in declaration_regex.search_all(semantic_line):
			var variable_name := declaration.get_string(1)
			if is_function_signature and variable_name == function_match.get_string(1) \
					and declaration.get_start(1) == function_match.get_start(1):
				continue
			var scope: Dictionary = declaration_scopes.back()
			if scope.has(variable_name):
				errors.append({"line": line_index, "message": "'%s' is already declared on line %d in this scope." % [variable_name, int(scope[variable_name]) + 1]})
			elif shader_builtins.has(variable_name):
				errors.append({"line": line_index, "message": "'%s' conflicts with a built-in shader variable." % variable_name})
			else:
				scope[variable_name] = line_index
				declarations[variable_name] = line_index
		var opens := semantic_line.count("{")
		var closes := semantic_line.count("}") - leading_closes
		if (is_function_signature or is_struct_signature) and opens > 0:
			opens -= 1
		for _open in opens:
			declaration_scopes.append({})
		for _close in closes:
			if declaration_scopes.size() > 1:
				declaration_scopes.pop_back()
	var stack: Array[Dictionary] = []
	var pairs := {")": "(", "]": "[", "}": "{"}
	var openings := ["(", "[", "{"]
	var in_block_comment := false
	var previous_semantic := ""
	for line_index in code.get_line_count():
		var line_text := code.get_line(line_index)
		var column := 0
		while column < line_text.length():
			if in_block_comment:
				var block_end := line_text.find("*/", column)
				if block_end < 0:
					break
				in_block_comment = false
				column = block_end + 2
				continue
			if line_text.substr(column, 2) == "/*":
				in_block_comment = true
				column += 2
				continue
			if line_text.substr(column, 2) == "//":
				break
			var character := line_text.substr(column, 1)
			if openings.has(character):
				stack.append({"character": character, "line": line_index})
			elif pairs.has(character):
				if stack.is_empty() or stack.back().character != pairs[character]:
					errors.append({"line": line_index, "message": "Unexpected closing '%s'." % character})
				else:
					stack.pop_back()
			column += 1
		var trimmed := line_text.strip_edges()
		if trimmed.begins_with("uniform ") and not trimmed.contains(";"):
			errors.append({"line": line_index, "message": "Uniform declaration needs a semicolon."})
		var semantic := syntax_lines[line_index].strip_edges()
		var is_uniform_group := RegEx.create_from_string("^group_uniforms(?:\\s+[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)?)?\\s*;").search(semantic) != null
		if semantic.begins_with("group_uniforms") and not is_uniform_group:
			errors.append({"line": line_index, "message": "Invalid uniform group declaration. Use group_uniforms Group.Subgroup; or group_uniforms;"})
		var is_return_statement := RegEx.create_from_string("^return(?:\\s+.+)?;?$").search(semantic) != null
		var previous_continues := false
		for operator in ["+", "-", "*", "/", "%", "=", "(", "[", ",", "?", ":", "&&", "||", "<", ">"]:
			if previous_semantic.ends_with(operator): previous_continues = true
		var next_continues := false
		for next_index in range(line_index + 1, syntax_lines.size()):
			var next_semantic := syntax_lines[next_index].strip_edges()
			if next_semantic.is_empty(): continue
			for operator in ["+", "-", "*", "/", "%", "&&", "||", "?", ":"]:
				if next_semantic.begins_with(operator): next_continues = true
			break
		if not is_uniform_group and not previous_continues and not next_continues \
				and RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*\\s*;?$").search(semantic) \
				and semantic.trim_suffix(";") not in ["discard", "return", "else", "break", "continue"]:
			errors.append({"line": line_index, "message": "Unexpected token '%s'." % semantic.trim_suffix(";")})
		elif RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*\\s+[A-Za-z_][A-Za-z0-9_]*\\s*;?$").search(semantic) \
				and not is_uniform_group and not is_return_statement and not semantic.begins_with("shader_type ") \
				and not semantic.begins_with("render_mode ") and not semantic.begins_with("struct ") \
				and declaration_regex.search(semantic) == null:
			errors.append({"line": line_index, "message": "Unrecognized statement."})
		var assignment := RegEx.create_from_string("^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(?:=|\\+=|-=|\\*=|/=)").search(semantic)
		if assignment != null:
			var assigned_name := assignment.get_string(1)
			if not declarations.has(assigned_name) and not shader_builtins.has(assigned_name):
				errors.append({"line": line_index, "message": "Unknown variable '%s'." % assigned_name})
		if not semantic.is_empty(): previous_semantic = semantic
	for opening in stack:
		errors.append({"line": int(opening.line), "message": "Unclosed '%s'." % opening.character})
	var unique := {}
	for error in errors:
		var key := "%d:%s" % [int(error.line), str(error.message)]
		unique[key] = error
	errors.assign(unique.values())
	errors.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.line) < int(b.line))
	for error in errors:
		var line := clampi(int(error.line), 0, maxi(code.get_line_count() - 1, 0))
		code.set_line_background_color(line, Color(0.42, 0.08, 0.08, 0.48))
	diagnostics.visible = not errors.is_empty()
	if errors.is_empty():
		diagnostics.text = ""
	else:
		var messages := PackedStringArray()
		for error in errors.slice(0, 4):
			messages.append("Line %d: %s" % [int(error.line) + 1, str(error.message)])
		diagnostics.text = "  •  ".join(messages)


func _lines_without_comments() -> PackedStringArray:
	var result := PackedStringArray()
	var in_block := false
	for raw_line in code.text.split("\n"):
		var line := raw_line
		var clean := ""
		var column := 0
		while column < line.length():
			if in_block:
				var end := line.find("*/", column)
				if end < 0:
					column = line.length()
					continue
				in_block = false
				column = end + 2
				continue
			if line.substr(column, 2) == "/*":
				in_block = true
				column += 2
				continue
			if line.substr(column, 2) == "//":
				break
			clean += line.substr(column, 1)
			column += 1
		result.append(clean)
	return result


func _code_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		FocusableKeyInput.current_focused_instance = null
		code.grab_focus()
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		if dedicated_mode:
			save_shortcut_requested.emit(event.shift_pressed)
		else:
			save()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and get_global_rect().has_point(event.position):
		FocusableKeyInput.current_focused_instance = null


func _complete_code() -> void:
	for completion in COMPLETIONS:
		code.add_code_completion_option(0, completion, completion)
	# Uniforms declared in this file are useful while writing later expressions.
	var uniform_regex := RegEx.new()
	uniform_regex.compile("uniform\\s+\\w+\\s+(\\w+)")
	for result in uniform_regex.search_all(code.text):
		var uniform_name := result.get_string(1)
		code.add_code_completion_option(0, uniform_name, uniform_name)
	code.update_code_completion_options(true)


func _make_highlighter() -> CodeHighlighter:
	var highlighter := CodeHighlighter.new()
	highlighter.number_color = Color("b5cea8")
	highlighter.symbol_color = Color("d4d4d4")
	highlighter.function_color = Color("dcdcaa")
	highlighter.member_variable_color = Color("9cdcfe")
	for keyword in COMPLETIONS:
		var token: String = keyword.get_slice(" ", 0).trim_suffix(";").trim_suffix("()")
		if token.is_valid_identifier():
			highlighter.add_keyword_color(token, Color("c586c0"))
	for type_name in ["float", "int", "bool", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D", "samplerCube", "void"]:
		highlighter.add_keyword_color(type_name, Color("4ec9b0"))
	highlighter.add_color_region("//", "", Color("6a9955"), true)
	highlighter.add_color_region("/*", "*/", Color("6a9955"), false)
	return highlighter
