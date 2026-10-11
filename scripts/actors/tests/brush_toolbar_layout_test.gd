extends SceneTree

var failures:=0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size=Vector2i(1500,800)
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio)
	studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio.open_source(null)
	studio.canvas.tool="brush"; studio.canvas.stroke_correct=true
	studio.canvas.correction_strength=1; studio.canvas.correction_scale=16
	studio._refresh_context()
	for width in [1500,900]:
		root.size=Vector2i(width,800)
		for frame in 12: await process_frame
		var row:=studio.context.find_child("BrushToolbarRow",true,false) as HBoxContainer
		for child in row.get_children():
			if child is PanelContainer and absf(child.position.y)>1:
				failures+=1; push_error("Brush control wrapped below the toolbar at width %s" % width)
		if studio._context_panel.size.x>studio._main_split.size.x+1:
			failures+=1; push_error("Brush toolbar overflows the workspace at width %s" % width)
		if width==1500:
			var scroll:=studio.context.find_child("BrushToolbarScroll",true,false) as ScrollContainer
			if scroll.get_h_scroll_bar().visible:
				failures+=1; push_error("Brush controls should fit without scrolling in a wide workspace")
			root.get_texture().get_image().save_png("res://.godot/brush_toolbar_single_row.png")
	studio.free()
	print("Brush toolbar layout checks: %d failures" % failures)
	quit(failures)
