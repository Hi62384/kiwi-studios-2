extends SceneTree
func _initialize() -> void:
	var path:=FileAccess.get_file_as_string("res://.godot/verification/clipboard_restart_path.txt")
	var store:=KiwiClipboardStore.new(path)
	var ok: bool=store.folder_valid("default") and store.data.entries.size()>=3
	print("PASS " if ok else "FAIL ","Persistent library reopens in a separate Godot process")
	quit(0 if ok else 1)
