extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size=Vector2i(1400,850)
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio)
	studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio.open_source(null)
	await process_frame
	print("Opening image/document picker")
	studio._choose_image()
	await process_frame
	for child in studio.get_children():
		if child is ActorProjectFilePicker:
			assert(child.visible,"Picker must be visible before the project scan completes")
			var deadline:=Time.get_ticks_msec()+15000
			while not child._scan_ready and Time.get_ticks_msec()<deadline: await process_frame
			assert(child._scan_ready,"Project scan completes")
			print("Picker opened: ",child.files.item_count," entries")
			child._resolve("")
	for frame in 5: await process_frame
	studio.queue_free(); await process_frame
	print("Open dialog check completed"); quit()
