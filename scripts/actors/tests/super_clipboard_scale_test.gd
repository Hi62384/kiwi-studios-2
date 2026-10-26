extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,900)
	var service:=KiwiSuperClipboardService.instance; service.store.close(); service.store=KiwiClipboardStore.new("user://clipboard_scale_"+ActorData.new_id())
	var object:=ActorObjectData.new(); object.type_id=&"material"; object.values={&"roughness":.5}
	var source:=service.store.save(object,"Material"); var next:=service.store.data.duplicate(true)
	for i in 999:
		var id:=ActorData.new_id(); next.entries[id]=next.entries[source].duplicate(true); next.entries[id].id=id; next.entries[id].name="Material %04d"%i
	service.store.commit("Populate test library",next)
	var path:=service.store.entry_path(source); var started:=Time.get_ticks_usec(); service.toggle()
	while service.window.files.item_count<1000: await process_frame
	var elapsed:=float(Time.get_ticks_usec()-started)/1000
	var ok: bool=service.window.files.item_count==1000 and not ResourceLoader.has_cached(path)
	print("PASS " if ok else "FAIL ","A 1,000-entry library opens incrementally without loading asset contents")
	var no_project:=service.drag_payload(PackedStringArray([source]))
	var internal: bool=no_project.get("type","")=="super_clipboard" and no_project.has("clipboard_ids")
	print("PASS " if internal else "FAIL ","Clipboard organization drags work without an open project")
	var report:=FileAccess.open("res://.godot/verification/super_clipboard_benchmark.json",FileAccess.WRITE); report.store_string(JSON.stringify({"entries":1000,"open_ms":elapsed,"metadata_bytes":JSON.stringify(service.store.data).length(),"asset_contents_loaded":ResourceLoader.has_cached(path)},"  ")); report.close()
	service.window._close(); quit(0 if ok and internal else 1)
