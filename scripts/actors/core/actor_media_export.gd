class_name ActorMediaExport
extends RefCounted
static func write_async(owner: Node, value: Variant, path: String, property: ActorProperty) -> bool:
	var worker := Thread.new()
	if worker.start(write.bind(value, path, property)) != OK: return false
	while worker.is_alive(): await owner.get_tree().process_frame
	return bool(worker.wait_to_finish())

## Real encoding, never a byte-copy with a misleading extension.
static func formats(property: ActorProperty, value: Variant) -> PackedStringArray:
	return _native_media_export().formats(property,value)

static func write(value: Variant, path: String, property: ActorProperty) -> bool:
	return _native_media_export().write(value,path,property)

static func _native_media_export() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","actor_media_export")
