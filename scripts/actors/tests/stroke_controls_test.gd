extends SceneTree
var failures:=0
var studio: TestStudio

class TestStudio extends KiwiImageWorkspace:
	func _persist_paint_presets(_path: String=PAINT_PRESETS_PATH) -> void: pass

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: execute.call_deferred()
func execute() -> void:
	await run()
	for frame in 10: await process_frame
	quit(failures)

func fixture(tool: String="brush") -> KiwiImageLayer:
	studio.canvas.cancel_gesture()
	studio.document=KiwiImageDocument.new(); studio.document.canvas_size=Vector2i(48,32)
	var layer:=KiwiImageLayer.create("basic",studio.document.canvas_size)
	var image:=Image.create(48,32,false,Image.FORMAT_RGBA8); image.fill(Color.RED); image.fill_rect(Rect2i(24,0,24,32),Color.BLUE)
	layer.texture=ImageTexture.create_from_image(image); layer.paint_base=layer.texture; studio.document.layers.append(layer)
	studio.canvas.document=studio.document; studio.canvas.selected.assign([layer.id]); studio.canvas.tool=tool
	studio.canvas.stroke_correct=true; studio.canvas.correction_scale=1; studio.canvas.correction_strength=1
	studio.canvas.brush_size=8; studio.canvas.brush_opacity=1; studio.canvas.hardness=1
	studio.canvas.paint_selection_only=false; studio.canvas.paint_new_layer=false; studio.canvas.fill_threshold=.01
	studio.canvas.color=Color.GREEN; studio._undo.clear(); studio._redo.clear()
	return layer

func button(point: Vector2,pressed: bool,control: bool=false) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	event.ctrl_pressed=control; event.position=studio.canvas.origin()+point*studio.canvas.zoom
	studio.canvas._input_canvas(event)

func motion(point: Vector2,control: bool) -> void:
	var event:=InputEventMouseMotion.new(); event.ctrl_pressed=control; event.button_mask=MOUSE_BUTTON_MASK_LEFT
	event.position=studio.canvas.origin()+point*studio.canvas.zoom; studio.canvas._input_canvas(event)
	studio.canvas._process(1.0/60)

func run() -> void:
	studio=TestStudio.new(); root.add_child(studio)
	var layer:=fixture(); studio._refresh_context()
	var scale:=studio.context.find_child("CorrectionScale",true,false) as DragNumber
	check(scale!=null,"Stroke correction exposes a scale control")
	var settings:=studio.context.find_child("StrokeSettings",true,false) as Button
	var toolbar:=studio.context.find_child("BrushToolbarRow",true,false)
	var settings_group: Node=settings
	while settings_group!=null and settings_group.get_parent()!=toolbar: settings_group=settings_group.get_parent()
	check(settings!=null and settings.visible and settings_group!=null and settings_group.get_index()==2,"Stroke correction settings remain beside the tool title before other toolbar groups")
	check(scale.get_parent().get_parent() is PopupPanel,"Detailed correction controls remain available in the compact settings popup")
	check(studio.context.find_child("BrushToolbarRow",true,false) is HBoxContainer,"Brush controls use a single non-wrapping toolbar row")
	scale.value=2.5; check(is_equal_approx(studio.canvas.correction_scale,2.5),"The scale field changes correction scale")
	var zoom:=studio.canvas.zoom
	var wheel:=InputEventMouseButton.new(); wheel.pressed=true; wheel.alt_pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_UP
	studio.canvas._input_canvas(wheel)
	check(is_equal_approx(studio.canvas.correction_scale,2.75) and is_equal_approx(scale.value,2.75),"Alt+wheel changes scale and updates the toolbar")
	check(is_equal_approx(studio.canvas.zoom,zoom),"Changing correction scale does not zoom the canvas")
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; studio.canvas._input_canvas(wheel)
	check(is_equal_approx(studio.canvas.correction_scale,2.5),"Alt+wheel down reverses the scale adjustment")
	wheel.alt_pressed=false; wheel.shift_pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_UP
	studio.canvas._input_canvas(wheel)
	check(is_equal_approx(studio.canvas.brush_size,9) and is_equal_approx(studio.canvas.correction_scale,2.5),"Shift+wheel changes brush size without changing correction scale")
	check(is_equal_approx(studio.canvas.zoom,zoom),"Shift+wheel brush size does not zoom the canvas")
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; studio.canvas._input_canvas(wheel)
	check(is_equal_approx(studio.canvas.brush_size,7.92),"Shift+wheel down preserves the existing proportional size adjustment")
	for active_tool in ["fill","pixel_select"]:
		studio.canvas.tool=active_tool; studio.canvas.pixel_mode="fill"
		wheel.button_index=MOUSE_BUTTON_WHEEL_UP; studio.canvas._input_canvas(wheel)
		check(is_equal_approx(studio.canvas.fill_threshold,.02),"Shift+wheel increases threshold for "+active_tool)
		wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; studio.canvas._input_canvas(wheel)
		check(is_equal_approx(studio.canvas.fill_threshold,.01),"Shift+wheel decreases threshold for "+active_tool)
	studio.canvas.tool="brush"
	wheel.shift_pressed=false; wheel.ctrl_pressed=true; studio.canvas._input_canvas(wheel)
	check(is_equal_approx(studio.canvas.brush_size,7.92) and is_equal_approx(studio.canvas.fill_threshold,.01),"Ctrl+wheel no longer changes brush size or threshold")
	var state:=studio.capture_state(); studio.canvas.correction_scale=1; studio.open_source(null,state)
	check(is_equal_approx(studio.canvas.correction_scale,2.5),"Correction scale survives image workspace switching")
	layer=fixture(); studio.canvas.paint_new_layer=true
	button(Vector2(12,16),true,true); button(Vector2(12,16),false,true)
	check(layer.texture.get_image().get_pixel(12,16).a==0 and layer.texture.get_image().get_pixel(32,16).a==1,"Ctrl+brush erases instead of painting")
	check(studio.document.layers.size()==1,"Temporary erasing does not create an empty stroke layer")
	studio.undo(); check(studio.document.layers[0].texture.get_image().get_pixel(12,16).a==1,"Temporary brush erasing supports undo")
	studio.redo(); check(studio.document.layers[0].texture.get_image().get_pixel(12,16).a==0,"Temporary brush erasing supports redo")
	layer=fixture(); button(Vector2(8,16),true); motion(Vector2(16,16),false)
	motion(Vector2(24,16),true); motion(Vector2(36,16),false); button(Vector2(36,16),false)
	check(layer.texture.get_image().get_pixel(19,16).a==0,"Releasing Ctrl does not restore erased pixels during a mixed stroke")
	check(layer.texture.get_image().get_pixel(36,16).g>.9,"Releasing Ctrl resumes painting during the same stroke")
	check(studio._undo.size()==1,"A mixed draw/erase gesture uses one undo entry")
	layer=fixture("fill"); button(Vector2(12,16),true,true); button(Vector2(12,16),false,true)
	check(layer.texture.get_image().get_pixel(12,16).a==0 and layer.texture.get_image().get_pixel(32,16).a==1,"Ctrl+bucket erases only the connected matching region")
	studio.undo(); check(studio.document.layers[0].texture.get_image().get_pixel(12,16).a==1,"Bucket erasing supports undo")
	for mode in ["brush","fill","fill_all"]:
		layer=fixture("pixel_select"); studio.canvas.pixel_mode="fill" if mode=="fill_all" else mode
		studio.canvas.pixel_match_all=mode=="fill_all"
		studio.canvas.pixel_source=layer.texture.get_image(); studio.canvas.pixel_domain=Rect2i(Vector2i.ZERO,studio.document.canvas_size)
		var mask:=Image.create(48,32,false,Image.FORMAT_RGBA8); mask.fill(Color.WHITE)
		studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=layer.id
		studio.canvas.sync_pixel_selection()
		button(Vector2(12,16),true,true); button(Vector2(12,16),false,true)
		check(not studio.canvas.selected_pixel(Vector2(12,16)) and studio.canvas.selected_pixel(Vector2(32,16)),"Ctrl subtracts pixels with selection "+mode)
		studio.undo(); check(studio.canvas.selected_pixel(Vector2(12,16)),"Ctrl selection "+mode+" supports undo")
	studio.canvas.pixel_mode="brush"; studio._refresh_context()
	check(studio.context.find_child("PixelBoxSelect",true,false)!=null,"Pixel selection keeps its Box Select toggle")
	for control in studio.context.find_children("*","Button",true,false):
		check(control.tooltip_text not in ["Box crop · C","Lasso crop · L"],"Pixel selection does not show standalone box/lasso crop icons")
	# Undo and selection changes launch asynchronous source captures. Let those
	# finish while their owning workspace still exists, before deleting fixtures.
	for frame in 24: await RenderingServer.frame_post_draw
	# The legacy workspace color-state control is deliberately not parented.
	# Tests own this orphan too; release it before the rendering server shuts down.
	studio.color_picker.queue_free(); studio.queue_free(); studio=null; scale=null; layer=null; state.clear()
	await process_frame; await process_frame
	print("Stroke control / modifier checks: %d failures" % failures)
