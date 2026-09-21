extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()

const SOURCE := """shader_type spatial;
uniform float ungrouped_before = 0.25;
group_uniforms Surface;
uniform float strength = 0.5;
group_uniforms Surface.Details;
uniform vec3 offset = vec3(1.0);
group_uniforms Surface;
uniform float roughness = 0.6;
group_uniforms;
uniform float ungrouped_after = 0.75;
void fragment() { ALBEDO = vec3(strength); }
"""

func run() -> void:
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var model := ActorTimeline.new()
	var clip := model.create_actor(registry.get_definition(&"image_3d"), 0.0)
	var actor := model.actor_for_id(clip.actor_id)
	var shader := Shader.new()
	shader.code = SOURCE
	var definition := registry.get_object_definition(&"shader_material")
	var object := definition.create_object()
	object.values[&"shader_path"] = shader
	actor.values[&"material"] = ActorObjectReference.from_object(object)
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, registry)
	var panel := VBoxContainer.new()
	inspector.fields.add_child(panel)
	var layout := inspector._shader_uniform_layout(shader, panel, actor.id, "GroupsTest")
	check(layout.size() == 5, "Group markers are not editable uniforms")
	var parents: Dictionary = {}
	for entry in layout: parents[entry.info.name] = entry.parent
	check(parents.ungrouped_before == panel and parents.ungrouped_after == panel, "group_uniforms; ends grouping")
	check(parents.strength == parents.roughness and parents.strength != panel, "Reopened groups share one category")
	check(parents.offset.get_parent().get_parent() == parents.strength, "Subgroup content nests under its group")
	var group_button := parents.strength.get_parent().get_child(0) as Button
	group_button.button_pressed = false
	check(not parents.strength.visible, "Uniform group collapses")
	var recreated := VBoxContainer.new()
	inspector.fields.add_child(recreated)
	var second := inspector._shader_uniform_layout(shader, recreated, actor.id, "GroupsTest")
	check(not second[1].parent.visible, "Group collapse state survives rebuild")
	inspector._add_shader_uniforms(actor, object, definition, panel)
	check(panel.find_child("Surface_reset", true, false) == null, "Group title has no reset button")
	model.edit_shader_uniform(actor, object, definition, &"strength", 0.9)
	check(object.values[&"uniforms"][&"strength"] == 0.9, "Grouped uniform edits retain original parameter names")
	model.history.undo()
	check(not object.values[&"uniforms"].has(&"strength"), "Grouped uniform edits undo normally")
	var file_path := "user://shader_group_material_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(object, file_path) == OK, "Save grouped material fixture")
	inspector.inspect_file_resource(file_path)
	var headers := inspector.find_children("Category_*", "Button", true, false)
	check(headers.any(func(button: Button): return button.text.contains("SURFACE")), "Filesystem material inspector displays shader groups")
	check(headers.any(func(button: Button): return button.text.contains("DETAILS")), "Filesystem material inspector displays subgroups")
	var editor := ShaderCodeEditor.new()
	root.add_child(editor)
	editor.code.text = SOURCE
	editor._validate_syntax()
	check(not editor.diagnostics.visible, "Group, subgroup, and end directives have no false syntax errors")
	editor.code.text = "shader_type spatial;\ngroup_uniforms Surface; uniform float strength;\nvoid fragment() { ALBEDO = vec3(strength); }"
	editor._validate_syntax()
	check(not editor.diagnostics.visible, "Inline group declaration is accepted")
	editor.code.text = "shader_type spatial;\ngroup_uniforms Broken\n"
	editor._validate_syntax()
	check(editor.diagnostics.visible, "Malformed group declaration still reports an error")
	check(editor.code.syntax_highlighter.get_keyword_color("group_uniforms") == Color("c586c0"), "group_uniforms has keyword highlighting")
	editor.free()
	inspector.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	await process_frame
	print("Shader uniform grouping checks: %d failures" % failures)
	quit(failures)
