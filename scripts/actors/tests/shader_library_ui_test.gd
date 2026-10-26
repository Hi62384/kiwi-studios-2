extends SceneTree
const Browser = preload("res://Workspaces/ShaderWorkspace/shader_sample_browser.gd")
const Catalog = preload("res://Workspaces/ShaderWorkspace/library/shader_sample_catalog.gd")
var failures := 0
class TestTabs:
	extends Node
	var shader_workspace: Node
	var opened: Shader
	func open_shader(shader: Shader) -> bool:
		opened = shader
		return true

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func wait_selection(browser: Control) -> void:
	for _frame in 120:
		if not browser._selection_busy and not browser._thumbnail_busy: return
		await process_frame

func run() -> void:
	root.size = Vector2i(1300, 850)
	var browser := Browser.new()
	browser.preferences_path = "user://shader_library_ui_test.cfg"
	root.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_selection(browser)
	var sample_count := browser._cards.size()
	check(sample_count >= 100, "Full sample catalog loads")
	check(browser.get_children().filter(func(node: Node): return node is SubViewport).size() == 2, "Only two reusable renderers are allocated for the entire library")
	browser.search.text = "water"
	browser.refresh()
	check(browser._cards.size() >= 3 and browser._cards.size() < sample_count, "Water search finds multiple actual sample contexts")
	browser.type_filter.select(2)
	browser.refresh()
	for card: Dictionary in browser._cards.values(): check(str(card.entry.shader_type) == "spatial", "Type filter stays strict with text search")
	browser.type_filter.select(0)
	browser.search.text = ""
	browser.set_templates(true)
	check(browser._cards.size() >= 20, "Separate complete templates tab loads")
	browser.set_templates(false)
	await wait_selection(browser)
	var selected := browser.selected.duplicate(true)
	browser.favorites = []
	browser.recent = []
	browser._toggle_favorite()
	browser._mark_used()
	var state := ConfigFile.new()
	check(state.load(browser.preferences_path) == OK, "Preferences are written")
	check(PackedStringArray(state.get_value("library", "favorites", [])).has(str(selected.id)), "Favorite persists to disk")
	browser.favorites = []
	browser.recent = []
	browser._load_preferences()
	check(browser.favorites.has(str(selected.id)) and browser.recent.has(str(selected.id)), "Favorites and recent survive reload")
	if DisplayServer.get_name() != "headless":
		var previous_clipboard := DisplayServer.clipboard_get()
		browser._copy()
		await process_frame
		# The Windows clipboard transports CRLF, while source resources can use
		# either LF or CRLF. Compare text, preserving all lines and final newlines.
		var copied := DisplayServer.clipboard_get().replace("\r\n", "\n")
		var expected := Catalog.get_code(selected).replace("\r\n", "\n")
		check(copied == expected, "Copy Code sends full source to clipboard (%d / %d characters)" % [copied.length(), expected.length()])
		DisplayServer.clipboard_set(previous_clipboard)
		for _frame in 100: await process_frame
		await wait_selection(browser)
		check(not browser._textures.is_empty(), "Lazy thumbnails capture actual rendered output")
		var cached_path: String = Browser.CACHE + browser._cache_key(selected) + ".png"
		check(FileAccess.file_exists(cached_path), "Thumbnail persists in cache")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/shader_library_browser.png")
	var tabs := TestTabs.new()
	root.add_child(tabs)
	tabs.add_to_group("actor_scene_tabs")
	var editor := ShaderCodeEditor.new()
	editor.dedicated_mode = true
	editor.auto_save_enabled = false
	root.add_child(editor)
	editor.hide()
	for entry in Catalog.get_entries():
		editor.code.text = str(entry.source)
		editor._validate_syntax()
		check(not editor.diagnostics.visible, "Editor accepts complete sample without false syntax diagnostics: " + str(entry.id))
	var original := Shader.new()
	original.code = "shader_type spatial; void fragment(){ALBEDO=vec3(0.4);}"
	editor.current_shader = original
	editor.code.text = "shader_type spatial; void fragment(){ALBEDO=vec3(0.9);} // unsaved"
	var before := editor.code.text
	editor._open_library_sample(selected)
	check(tabs.opened != null and tabs.opened != original, "Open in Editor creates a fresh shader resource")
	check(tabs.opened.code == Catalog.get_code(selected), "New tab receives complete sample code")
	check(editor.code.text == before and not original.code.contains("unsaved"), "Open sample preserves old editor unsaved work")
	var copy_path := "user://shader_library_ui_copy.gdshader"
	check(Browser.write_shader_copy(copy_path, str(selected.source)) == OK, "Create Shader File writes a shader copy")
	var saved_shader := ResourceLoader.load(copy_path, "Shader", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	check(saved_shader != null and saved_shader.code == selected.source, "Saved copy loads as a complete shader resource")
	check(Browser.write_shader_copy(str(selected.path), str(selected.source)) == ERR_UNAUTHORIZED, "Library originals cannot be overwritten by Create Shader File")
	DirAccess.remove_absolute(copy_path)
	var workspace = preload("res://Workspaces/ShaderWorkspace/shader_workspace.gd").new()
	root.add_child(workspace)
	var particle_shader := Shader.new()
	particle_shader.code = "shader_type particles; uniform float speed=1.0; void start(){VELOCITY=vec3(0.0,speed,0.0);}"
	workspace.open_source(particle_shader)
	check(workspace.particle_preview.visible and workspace.particle_preview.emitting and not workspace.mesh_holder.visible, "Full workspace uses an actual particle preview")
	check(workspace.particle_preview.process_material.shader.code == particle_shader.code, "Particle preview uses the editor source")
	workspace._set_preview_parameter(&"speed", 2.0)
	check(workspace.particle_material.get_shader_parameter(&"speed") == 2.0, "Particle preview uniforms update live")
	var screen_shader := Shader.new()
	screen_shader.code = "shader_type canvas_item; uniform sampler2D screen_texture: hint_screen_texture; void fragment(){COLOR=texture(screen_texture,SCREEN_UV);}"
	workspace.open_source(screen_shader)
	check(workspace.canvas_preview_background.visible and workspace.canvas_preview.size == Vector2(workspace.viewport.size), "Full workspace postprocessing has a real screen-input scene")
	workspace.hide()
	check(workspace.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden Shader Workspace stops rendering")
	workspace.queue_free()
	editor.queue_free()
	tabs.queue_free()
	browser.queue_free()
	DirAccess.remove_absolute("user://shader_library_ui_test.cfg")
	await process_frame
	print("SHADER_LIBRARY_UI_TEST: %s (%d samples)" % ["PASS" if failures == 0 else "FAIL (%d)" % failures, sample_count])
	call_deferred("quit", 0 if failures == 0 else 1)
