class_name InteractionHints
extends RefCounted
## Active interactions publish their own hints; ending one reveals the previous.
signal changed(text: String)
var _contexts: Dictionary = {}
var _idle_text: String = ""


func set_idle(text: String) -> void:
	_idle_text = text
	_publish()


func begin(owner: Object, text: String) -> void:
	_contexts.erase(owner.get_instance_id())
	_contexts[owner.get_instance_id()] = text
	_publish()


func end(owner: Object) -> void:
	_contexts.erase(owner.get_instance_id())
	_publish()


func _publish() -> void:
	changed.emit(_idle_text if _contexts.is_empty() else str(_contexts.values().back()))
