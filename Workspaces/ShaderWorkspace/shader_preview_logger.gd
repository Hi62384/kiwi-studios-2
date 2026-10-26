extends Logger
## Engine shader diagnostics, including errors generated on the render thread.
## Never call logging functions from this callback (that would recurse).
var _mutex := Mutex.new()
var _messages := PackedStringArray()
var capturing := false

func clear() -> void:
	_mutex.lock()
	_messages.clear()
	_mutex.unlock()

func messages() -> PackedStringArray:
	_mutex.lock()
	var result := _messages.duplicate()
	_mutex.unlock()
	return result

func _log_error(_function: String, _file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array[ScriptBacktrace]) -> void:
	if not capturing or error_type != Logger.ERROR_TYPE_SHADER:
		return
	_mutex.lock()
	_messages.append("Line %d: %s" % [line, rationale if not rationale.is_empty() else code])
	_mutex.unlock()
