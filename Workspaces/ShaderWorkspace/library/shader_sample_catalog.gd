class_name ShaderSampleCatalog
extends RefCounted
## Complete standalone shader resources. Originals are immutable; consumers open copies.

const LibraryData = preload("res://Workspaces/ShaderWorkspace/library/shader_library_data.gd")
static var _entries: Array[Dictionary] = []

static func get_entries() -> Array[Dictionary]:
	if _entries.is_empty():
		for raw: Dictionary in LibraryData.ENTRIES:
			var item := raw.duplicate(true)
			item["type"] = item["shader_type"]
			item["is_template"] = item["template"]
			item["supported_targets"] = item["targets"]
			item["preview"] = {"geometry": item["preview_mesh"], "animated": item["animated"], "requires_forward_plus": item["requires_forward_plus"]}
			_entries.append(item)
	return _entries.duplicate(true)

static func get_entry(id: String) -> Dictionary:
	for item: Dictionary in get_entries():
		if str(item["id"]) == id:
			return item
	return {}

static func get_code(entry_or_id: Variant) -> String:
	var item: Dictionary = entry_or_id if entry_or_id is Dictionary else get_entry(str(entry_or_id))
	return str(item.get("source", ""))

static func entries() -> Array[Dictionary]:
	return get_entries()

static func entry(id: String) -> Dictionary:
	return get_entry(id)
