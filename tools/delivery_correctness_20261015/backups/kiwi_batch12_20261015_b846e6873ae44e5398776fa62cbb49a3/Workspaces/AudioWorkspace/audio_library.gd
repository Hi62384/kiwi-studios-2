class_name KiwiAudioLibrary
extends VBoxContainer
signal selected(entry: Dictionary)
signal preview_requested(entry: Dictionary)
signal add_requested(entry: Dictionary)
const CONFIG_PATH := "user://audio_workspace/library.cfg"
class DraggableList extends ItemList:
	func _get_drag_data(_position: Vector2) -> Variant:
		var indices := get_selected_items()
		if indices.is_empty(): return null
		var entry: Dictionary = get_item_metadata(indices[0])
		if bool(entry.get("project_indexed", false)) and not KiwiAudioAssetIndex.usable(entry): return null
		var label := Label.new()
		label.text = str(entry.get("label", "Audio"))
		set_drag_preview(label)
		if entry.get("kind", "") == "generator":
			var library := get_parent() as KiwiAudioLibrary
			if library != null and library.generator_drag_payload.is_valid(): return library.generator_drag_payload.call(entry)
			return {"generator": entry.duplicate(true)}
		# Project assets use the guarded library path again at drop time.
		if bool(entry.get("project_indexed", false)): return {"audio_library": entry.duplicate(true)}
		if entry.has("source"): return {"audio_source": entry.source, "label": entry.get("label", "Audio")}
		return {"audio_library": entry}
var search := LineEdit.new()
var category := OptionButton.new()
var list := DraggableList.new()
var entries: Array[Dictionary] = []
var favorites: Dictionary = {}
var recent: Array[String] = []
var imported: Array[Dictionary] = []
var current: Dictionary = {}
var generator_drag_payload := Callable()
var _index := KiwiAudioAssetIndex.new()
var _project_roots: Array[String] = []
var _project_entries: Array[Dictionary] = []
var _index_generation := 0
var _project_key := ""
var _source_menu := OptionButton.new()
var _scan_status := Label.new()
var _refresh_button := Button.new()
var _cancel_button := Button.new()
var _remove_button := Button.new()
var _preview_button := Button.new()
var _add_button := Button.new()
var _folder_dialog := FileDialog.new()

func _ready() -> void:
	custom_minimum_size.x = 185
	_project_key = ProjectSettings.globalize_path("res://").sha256_text()
	var title := Label.new()
	title.text = "AUDIO LIBRARY"
	title.add_theme_color_override("font_color", Color("6bdbc0"))
	add_child(title)
	search.placeholder_text = "Search sounds, instruments…"
	search.clear_button_enabled = true
	add_child(search)
	search.text_changed.connect(func(_text: String): refresh())
	for kind in ["All", "Sound Effects", "Instruments", "Imported", "Project", "Presets", "Favorites", "Recent", "Templates"]: category.add_item(kind)
	add_child(category)
	category.item_selected.connect(func(_position: int): refresh())
	_build_project_controls()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	list.fixed_column_width = 175
	list.max_text_lines = 2
	add_child(list)
	list.item_selected.connect(_selected)
	list.item_activated.connect(func(_position: int): _request_preview())
	var row := HBoxContainer.new()
	add_child(row)
	_preview_button.text = "▶"
	_preview_button.tooltip_text = "Preview selected sound"
	row.add_child(_preview_button)
	_preview_button.pressed.connect(_request_preview)
	_add_button.text = "+ Add"
	row.add_child(_add_button)
	_add_button.pressed.connect(_request_add)
	var favorite := Button.new()
	favorite.text = "☆"
	favorite.tooltip_text = "Toggle favorite"
	row.add_child(favorite)
	favorite.pressed.connect(toggle_favorite)
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var saved_favorites: Variant = config.get_value("library", "favorites", {})
		if saved_favorites is Dictionary: favorites = saved_favorites.duplicate(true)
		var saved_recent: Variant = config.get_value("library", "recent", [])
		if saved_recent is Array:
			for id in saved_recent:
				if id is String and recent.size() < 40 and not recent.has(id): recent.append(id)
		var saved_imported: Variant = config.get_value("library", "imported", [])
		if saved_imported is Array:
			for entry in saved_imported:
				if entry is Dictionary: imported.append(entry.duplicate(true))
		var roots: Variant = config.get_value("project_index", _project_key, [])
		if roots is Array:
			for value in roots:
				var root := KiwiAudioAssetIndex.canonical_root(str(value))
				if not root.is_empty() and not _project_roots.has(root) and _project_roots.size() < KiwiAudioAssetIndex.MAX_ROOTS: _project_roots.append(root)
	_update_sources()
	reload()
	if not _project_roots.is_empty(): _start_scan()

func _build_project_controls() -> void:
	add_child(_index)
	_index.progress_changed.connect(func(message: String):
		if not message.is_empty(): _scan_status.text = message)
	_index.scan_finished.connect(_scan_finished)
	var heading := Label.new()
	heading.text = "PROJECT FOLDERS"
	add_child(heading)
	_source_menu.clip_text = true
	_source_menu.tooltip_text = "Only selected res:// folders are scanned. .godot, .git and linked paths are excluded."
	add_child(_source_menu)
	var row := HBoxContainer.new()
	add_child(row)
	var choose := Button.new()
	choose.text = "+ Folder"
	choose.tooltip_text = "Add an audio folder inside this project"
	row.add_child(choose)
	choose.pressed.connect(func(): _folder_dialog.popup_centered_ratio(0.65))
	_remove_button.text = "−"
	_remove_button.tooltip_text = "Remove selected index source; imported files and favorites are kept"
	row.add_child(_remove_button)
	_remove_button.pressed.connect(_remove_source)
	_refresh_button.text = "↻"
	_refresh_button.tooltip_text = "Refresh selected project folders (bounded metadata scan)"
	row.add_child(_refresh_button)
	_refresh_button.pressed.connect(_start_scan)
	_cancel_button.text = "Stop"
	_cancel_button.disabled = true
	row.add_child(_cancel_button)
	_cancel_button.pressed.connect(_cancel_scan)
	_scan_status.text = "Add a project folder to index audio."
	_scan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scan_status.add_theme_font_size_override("font_size", 11)
	_scan_status.tooltip_text = "One background worker; at most 2,048 assets, 512 folders, depth 16, 20,000 entries, 15 seconds and 16 MiB header reads per scan. Audio is loaded only for preview/add."
	add_child(_scan_status)
	_folder_dialog.access = FileDialog.ACCESS_RESOURCES
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.current_dir = "res://"
	_folder_dialog.title = "Index a project audio folder"
	add_child(_folder_dialog)
	_folder_dialog.dir_selected.connect(_add_source)

func _add_source(value: String) -> void:
	var root := KiwiAudioAssetIndex.canonical_root(value)
	if root.is_empty() or KiwiAudioAssetIndex.path_state(root, true) != "available":
		_scan_status.text = "Choose a readable res:// folder without links or excluded directories."
		return
	for existing in _project_roots:
		if KiwiAudioAssetIndex.contains_path(existing, root):
			_scan_status.text = "That folder is already included. Refresh to scan it again."
			return
	var next: Array[String] = []
	for existing in _project_roots:
		if not KiwiAudioAssetIndex.contains_path(root, existing): next.append(existing)
	if next.size() >= KiwiAudioAssetIndex.MAX_ROOTS:
		_scan_status.text = "Up to eight project folders can be indexed. Remove one first."
		return
	next.append(root)
	_project_roots = next
	_update_sources()
	_start_scan()
	_save("project_index")

func _remove_source() -> void:
	var position := _source_menu.selected
	if position < 0 or position >= _project_roots.size(): return
	_project_roots.remove_at(position)
	_index.cancel()
	_index_generation = -1
	var kept: Array[Dictionary] = []
	for entry in _project_entries:
		for root in _project_roots:
			if KiwiAudioAssetIndex.contains_path(root, str(entry.source)):
				kept.append(entry)
				break
	_project_entries = kept
	_update_sources()
	reload()
	if _project_roots.is_empty():
		_cancel_button.disabled = true
		_scan_status.text = "No project folders selected. Imported files and favorites are kept."
	else: _start_scan()
	_save("project_index")

func _update_sources() -> void:
	_source_menu.clear()
	for root in _project_roots:
		_source_menu.add_item(root)
		_source_menu.get_popup().set_item_tooltip(_source_menu.item_count - 1, root)
	_source_menu.disabled = _project_roots.is_empty()
	_remove_button.disabled = _project_roots.is_empty()
	_refresh_button.disabled = _project_roots.is_empty()

func _start_scan() -> void:
	if _project_roots.is_empty(): return
	_index_generation = _index.request(_project_roots, _project_entries)
	_cancel_button.disabled = false
	_scan_status.text = "Scanning project audio headers…"

func _cancel_scan() -> void:
	_index.cancel()
	_index_generation = -1
	_cancel_button.disabled = true
	_scan_status.text = "Indexing stopped. Previous results are kept."

func _scan_finished(generation: int, result: Dictionary) -> void:
	if generation != _index_generation: return
	_cancel_button.disabled = true
	if not str(result.get("error", "")).is_empty():
		_scan_status.text = str(result.error)
		return
	if bool(result.get("cancelled", false)): return
	_project_entries.assign(result.get("entries", []))
	reload()
	var unavailable := 0
	for entry in _project_entries:
		if str(entry.get("asset_state", "unverified")) != "available": unavailable += 1
	_scan_status.text = "%d indexed · %d unavailable/unchecked" % [_project_entries.size(), unavailable]
	if bool(result.get("partial", false)): _scan_status.text += " · partial scan"
	var details := str(result.get("limit_reason", ""))
	if int(result.get("unreadable_folders", 0)) > 0: details += "\n%d missing, blocked or unreadable folders." % int(result.unreadable_folders)
	if int(result.get("skipped_links", 0)) > 0: details += "\n%d linked entries skipped." % int(result.skipped_links)
	_scan_status.tooltip_text = "%d audio files checked; %d directory entries visited; %d header bytes read.\n%s\n~ durations are header estimates; preview uses the existing scene loader." % [int(result.get("inspected", 0)), int(result.get("visited", 0)), int(result.get("header_bytes", 0)), details]
	if not details.strip_edges().is_empty(): _scan_status.text += "\n" + details.strip_edges()

func reload() -> void:
	entries.clear()
	for preset in KiwiAudioSynthesis.presets():
		var entry: Dictionary = preset.duplicate(true)
		entry.kind = "generator"
		entries.append(entry)
	for preset in KiwiAudioInstruments.presets():
		var entry: Dictionary = preset.duplicate(true)
		entry.kind = "instrument"
		entry.category = "Instruments"
		entries.append(entry)
	for label in KiwiAudioTemplates.names(): entries.append({"id": "template_" + label, "label": label, "kind": "template", "category": "Templates"})
	var by_id: Dictionary = {}
	for entry in _project_entries: by_id[str(entry.id)] = entry
	for original in imported:
		var entry := original.duplicate(true)
		entry.origin = "imported"
		var id := str(entry.get("id", ""))
		if by_id.has(id):
			# A manually imported source keeps its existing load semantics even if
			# an index source also covers it. Do not persist index state into imports.
			entry.project_member = true
			entry.description = str(entry.get("description", entry.get("source", ""))) + "\nAlso included in the project index."
			by_id.erase(id)
		entries.append(entry)
	for entry in by_id.values(): entries.append(entry)
	var directory := DirAccess.open("user://audio_workspace/presets")
	if directory != null:
		for file in directory.get_files():
			if file.get_extension() != "tres": continue
			var path := "user://audio_workspace/presets/" + file
			var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
			if preset != null: entries.append({"id": preset.id, "label": preset.label, "kind": "preset", "category": "Presets", "preset": preset, "path": path})
	refresh()

func refresh() -> void:
	var selected_id := str(current.get("id", ""))
	list.clear()
	var query := search.text.to_lower().strip_edges()
	var filter := category.get_item_text(category.selected)
	var filtered: Array[Dictionary] = []
	for entry in entries:
		var id := str(entry.get("id", ""))
		var kind := str(entry.get("kind", ""))
		if not query.is_empty() and not (str(entry.get("label", "")) + " " + str(entry.get("category", "")) + " " + str(entry.get("description", "")) + " " + str(entry.get("source", ""))).to_lower().contains(query): continue
		if filter == "Sound Effects" and kind != "generator": continue
		if filter == "Instruments" and kind != "instrument": continue
		if filter == "Imported" and (kind != "asset" or str(entry.get("origin", "imported")) != "imported"): continue
		if filter == "Project" and not bool(entry.get("project_indexed", false)) and not bool(entry.get("project_member", false)): continue
		if filter == "Presets" and kind != "preset": continue
		if filter == "Templates" and kind != "template": continue
		if filter == "Favorites" and not favorites.has(id): continue
		if filter == "Recent" and not recent.has(id): continue
		filtered.append(entry)
	if filter == "Recent": filtered.sort_custom(func(a: Dictionary, b: Dictionary): return recent.find(str(a.id)) < recent.find(str(b.id)))
	else: filtered.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("category", "")) + str(a.label) < str(b.get("category", "")) + str(b.label))
	current = {}
	for entry in filtered:
		var text := ("★ " if favorites.has(str(entry.id)) else "") + str(entry.label) + "  ·  " + str(entry.get("category", "Audio"))
		if entry.has("duration"): text += "  %s%.2fs" % ["~" if bool(entry.get("duration_estimated", false)) else "", float(entry.duration)]
		if bool(entry.get("project_indexed", false)):
			var state := str(entry.get("asset_state", "unverified"))
			if state != "available": text += " · " + state
		var position := list.add_item(text)
		list.set_item_metadata(position, entry)
		list.set_item_tooltip(position, str(entry.get("description", entry.label)))
		if str(entry.id) == selected_id:
			current = entry
			list.select(position)
	_update_actions()
	if not selected_id.is_empty() and (current.is_empty() or bool(current.get("project_indexed", false))): selected.emit(current)

func _selected(position: int) -> void:
	current = list.get_item_metadata(position)
	remember(str(current.id))
	_update_actions()
	selected.emit(current)

func _update_actions() -> void:
	var unavailable := current.is_empty() or (bool(current.get("project_indexed", false)) and str(current.get("asset_state", "unverified")) != "available")
	_preview_button.disabled = unavailable
	_add_button.disabled = unavailable

func _can_use_current() -> bool:
	if current.is_empty(): return false
	if bool(current.get("project_indexed", false)) and not KiwiAudioAssetIndex.usable(current):
		_scan_status.text = "Project asset is missing, unreadable or blocked. Refresh its folder."
		return false
	return true

func _request_preview() -> void:
	if _can_use_current(): preview_requested.emit(current)

func _request_add() -> void:
	if _can_use_current(): add_requested.emit(current)

func remember(id: String) -> void:
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > 40: recent.resize(40)
	_save("recent", id)

func add_asset(source: Variant, label: String, duration: float) -> void:
	if not source is String: return
	var id := "asset_" + str(source).sha256_text()
	for entry in imported:
		if str(entry.id) == id: return
	imported.append({"id": id, "label": label, "kind": "asset", "category": "Imported", "source": source, "duration": duration})
	_save("imported", id)
	reload()

func toggle_favorite() -> void:
	if current.is_empty(): return
	var id := str(current.id)
	if favorites.has(id): favorites.erase(id)
	else: favorites[id] = true
	_save("favorites", id)
	refresh()

func _save(field: String, changed_id: String = "") -> void:
	# Reload first, then modify only the requested field. Preserve unknown keys,
	# sources for other projects, and edits made by another library instance.
	var config := ConfigFile.new()
	var loaded := config.load(CONFIG_PATH)
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		_scan_status.text = "Library settings could not be read; existing settings were not overwritten."
		return
	match field:
		"favorites":
			var saved: Variant = config.get_value("library", "favorites", {})
			var merged: Dictionary = saved.duplicate(true) if saved is Dictionary else {}
			if favorites.has(changed_id): merged[changed_id] = true
			else: merged.erase(changed_id)
			favorites = merged
			config.set_value("library", "favorites", favorites)
		"recent":
			var saved: Variant = config.get_value("library", "recent", [])
			var merged: Array[String] = [changed_id]
			if saved is Array:
				for id in saved:
					if id is String and merged.size() < 40 and not merged.has(id): merged.append(id)
			for id in recent:
				if merged.size() < 40 and not merged.has(id): merged.append(id)
			recent = merged
			config.set_value("library", "recent", recent)
		"imported":
			var saved: Variant = config.get_value("library", "imported", [])
			var merged: Array[Dictionary] = []
			if saved is Array:
				for entry in saved:
					if entry is Dictionary: merged.append(entry.duplicate(true))
			for entry in imported:
				var exists := false
				for other in merged:
					if str(other.get("id", "")) == str(entry.get("id", "")): exists = true
				if not exists: merged.append(entry.duplicate(true))
			imported = merged
			config.set_value("library", "imported", imported)
		"project_index": config.set_value("project_index", _project_key, _project_roots)
		_: return
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://audio_workspace"))
	if error == OK: error = config.save(CONFIG_PATH)
	if error != OK: _scan_status.text = "Library settings could not be saved; session changes are still available."

func remember_effect(id: String) -> void:
	remember("effect_" + id)

func ranked_effects() -> Array[Dictionary]:
	var definitions := KiwiAudioEffects.catalog()
	definitions.sort_custom(func(a: Dictionary, b: Dictionary):
		var ai := recent.find("effect_" + str(a.id))
		var bi := recent.find("effect_" + str(b.id))
		if ai < 0: ai = 100000
		if bi < 0: bi = 100000
		if ai != bi: return ai < bi
		return str(a.category) + str(a.label) < str(b.category) + str(b.label))
	return definitions

static func valid_entry(value: Variant) -> bool:
	if not value is Dictionary: return false
	var entry: Dictionary = value
	match str(entry.get("kind", "")):
		"generator": return not KiwiAudioSynthesis.preset(str(entry.get("id", ""))).is_empty()
		"instrument":
			for preset in KiwiAudioInstruments.presets():
				if str(preset.id) == str(entry.get("id", "")): return true
			return false
		"asset":
			if bool(entry.get("project_indexed", false)): return KiwiAudioAssetIndex.usable(entry)
			return entry.get("source") is AudioStream or (entry.get("source") is String and str(entry.source).get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"])
		"template": return str(entry.get("label", "")) in KiwiAudioTemplates.names()
		"preset":
			var preset: Variant = entry.get("preset")
			return preset is KiwiAudioPreset and str(preset.kind) in ["generator", "instrument", "pattern", "effects", "composition"] and (preset.kind != "composition" or preset.composition != null)
	return false
