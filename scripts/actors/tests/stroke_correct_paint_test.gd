extends SceneTree
var failures:=0
var studio: KiwiImageWorkspace

class SettingsStudio extends KiwiImageWorkspace:
	var saves:=0
	var saved_strength:=0.0
	func _persist_paint_presets(_path: String=PAINT_PRESETS_PATH) -> void:
		saves+=1; saved_strength=canvas.correction_strength

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: run.call_deferred()

func blank(size: Vector2i=Vector2i(256,192)) -> KiwiImageLayer:
	studio.canvas.cancel_gesture()
	studio.document=KiwiImageDocument.new(); studio.document.canvas_size=size
	var layer:=KiwiImageLayer.create("basic",size); studio.document.layers.append(layer)
	studio.canvas.document=studio.document; studio.canvas.selected.assign([layer.id])
	studio.canvas.tool="brush"; studio.canvas._active_mode="freehand"
	studio.canvas.stroke_correct=true; studio.canvas.correction_strength=.85
	studio.canvas.correction_scale=1.0
	studio.canvas.brush_size=12; studio.canvas.brush_opacity=.4; studio.canvas.hardness=.85
	studio.canvas.color=Color.BLUE; studio.canvas.paint_new_layer=false; studio.canvas.paint_selection_only=false
	studio._undo.clear(); studio._redo.clear(); return layer

func draw_path(start: Vector2,count: int=120,cadence: int=4) -> Vector2:
	studio.canvas._begin_paint(start)
	var began:=studio.canvas._corrector._last_time
	var point:=start
	for i in range(1,count):
		point=start+Vector2(i,8*sin(i*.04)+sin(i*1.7))
		studio.canvas._corrector.add(point,began+i/120.0)
		if i%cadence==0: studio.canvas._flush_corrected_stroke()
	studio.canvas._flush_corrected_stroke(); return point

func run() -> void:
	var settings:=SettingsStudio.new(); root.add_child(settings)
	settings.canvas.tool="brush"; settings.canvas.stroke_correct=true; settings._refresh_context()
	var slider:=settings.context.find_child("CorrectionStrength",true,false) as HSlider
	slider.drag_started.emit(); slider.value=25; slider.value=75
	check(settings.saves==0 and is_equal_approx(settings.canvas.correction_strength,.75),"Dragging strength previews changes without repeatedly saving preferences")
	slider.drag_ended.emit(true)
	check(settings.saves==1 and is_equal_approx(settings.saved_strength,.75),"Releasing the strength slider saves its final value")
	slider.value=50
	check(settings.saves==2 and is_equal_approx(settings.saved_strength,.5),"Keyboard strength changes are saved immediately")
	await check_actual_input(settings)
	settings.free()
	studio=KiwiImageWorkspace.new(); root.add_child(studio)
	var layer:=blank()
	var endpoint:=draw_path(Vector2(30,60))
	var preview_bytes:=studio.canvas._paint_image.get_data()
	studio.canvas._flush_corrected_stroke()
	check(studio.canvas._paint_image.get_data()==preview_bytes,"An unchanged corrected preview never adds paint")
	if DisplayServer.get_name()!="headless": check(layer.texture.get_image().get_data()==preview_bytes,"The GPU preview contains the corrected pixels")
	studio.canvas._finish(endpoint)
	check(layer.texture.get_image().get_data()==preview_bytes,"Finalizing uses exactly the corrected preview pixels")
	var pixels:=layer.texture.get_image(); var peak:=0.0
	for x in range(30,150):
		var covered:=false
		for y in range(45,80): peak=maxf(peak,pixels.get_pixel(x,y).a); covered=covered or pixels.get_pixel(x,y).a>.1
		check(covered,"Corrected brush has no gaps at x="+str(x))
	check(peak<=.405 and peak>.3,"Repeated tail revision preserves the requested translucent opacity")
	check(studio._undo.size()==1,"A corrected stroke creates one undo entry")
	studio.undo(); check(studio.document.layers[0].texture.get_image().get_used_rect().size==Vector2i.ZERO,"Undo restores untouched pixels")
	studio.redo(); check(studio.document.layers[0].texture.get_image().get_data()==preview_bytes,"Redo restores the exact final pixels")
	layer=blank(); endpoint=draw_path(Vector2(30,60),120,1); studio.canvas._finish(endpoint)
	check(layer.texture.get_image().get_data()==preview_bytes,"Preview cadence does not change the finished stroke's thickness or opacity")
	layer=blank(); draw_path(Vector2(20,40),40); studio.canvas.cancel_gesture()
	check(studio.document.layers[0].texture.get_image().get_used_rect().size==Vector2i.ZERO and studio._undo.is_empty(),"Cancellation restores pixels without committing history")
	layer=blank(); studio.canvas.paint_new_layer=true
	endpoint=draw_path(Vector2(20,40),40); studio.canvas._finish(endpoint)
	check(studio.document.layers.size()==2 and studio._undo.size()==1,"Generated corrected stroke layers commit as one action")
	studio.undo(); check(studio.document.layers.size()==1,"Undo removes a generated corrected stroke layer")
	layer=blank()
	var selection:=Image.create(256,192,false,Image.FORMAT_RGBA8); selection.fill(Color.TRANSPARENT); selection.fill_rect(Rect2i(0,0,80,192),Color.WHITE)
	studio.canvas.selection=selection; studio.canvas.paint_selection_only=true
	endpoint=draw_path(Vector2(30,60)); studio.canvas._finish(endpoint)
	check(layer.texture.get_image().get_pixel(40,65).a>0 and layer.texture.get_image().get_pixel(110,60).a==0,"Correction honors selected-only painting")
	layer=blank(); layer.position=Vector2(30,20); layer.rotation=.4
	var start:=studio.document.world_transform(layer)*Vector2(50,60)
	endpoint=draw_path(start,40); studio.canvas._finish(endpoint)
	check(layer.texture.get_image().get_pixel(50,60).a>.1,"Corrected drawing uses the transformed layer's local pixels")
	layer=blank(); studio.canvas.zoom=2.5; studio.canvas.pan=Vector2(200,-80)
	endpoint=draw_path(Vector2(30,60)); studio.canvas._finish(endpoint)
	check(layer.texture.get_image().get_data()==preview_bytes,"Zoom and pan do not change document-space stroke correction")
	layer=blank(); studio.canvas.brush_opacity=1; studio.canvas.color=Color(.2,.4,.8)
	layer.properties.value_basics={"brightness":.1}
	endpoint=draw_path(Vector2(30,60)); studio.canvas._finish(endpoint)
	var source:=layer.texture.get_image().get_pixel(70,68)
	check(absf(source.r-.1)<.02 and absf(source.g-.3)<.02 and absf(source.b-.7)<.02,"Corrected painting uses the inverse of final color adjustments")
	layer=blank(); studio.canvas.stroke_correct=false; studio.canvas._begin_paint(Vector2(50,60))
	check(studio.canvas._corrector==null,"Disabled correction follows the existing painting path")
	studio.canvas._finish(Vector2(50,60))
	layer=blank(); studio.canvas.correction_strength=0; studio.canvas._begin_paint(Vector2(50,60))
	check(studio.canvas._corrector==null,"Zero strength follows the existing uncorrected path")
	studio.canvas._finish(Vector2(50,60))
	for mode in ["line","curve","circle"]:
		layer=blank(); studio.canvas._active_mode=mode; studio.canvas._begin_paint(Vector2(50,60))
		check(studio.canvas._corrector==null and studio.canvas._drag=="shape_stroke","Correction preserves "+mode+" mode")
		studio.canvas.cancel_gesture()
	layer=blank(); studio.canvas.tool="eraser"; studio.canvas._begin_paint(Vector2(50,60))
	check(studio.canvas._corrector==null,"Eraser does not use stroke correction"); studio.canvas.cancel_gesture()
	layer=blank(Vector2i(1600,1200)); studio.canvas.brush_size=240
	var started:=Time.get_ticks_usec(); endpoint=draw_path(Vector2(400,400),80); studio.canvas._finish(endpoint)
	print("Large-image 240px corrected brush, 20 preview updates: %.1f ms" % [(Time.get_ticks_usec()-started)/1000.0])
	check(layer.texture.get_image().get_pixel(440,400).a>.1,"Large corrected brushes produce their expected coverage")
	studio.canvas.stroke_correct=true; studio.canvas.correction_strength=.72
	var preset:=studio._current_paint_preset("Corrected brush")
	check(preset.stroke_correct and is_equal_approx(preset.correction_strength,.72),"Brush presets include correction settings")
	var tab_state:=studio.capture_state(); studio.canvas.stroke_correct=false; studio.canvas.correction_strength=.1
	studio.open_source(null,tab_state)
	check(studio.canvas.stroke_correct and is_equal_approx(studio.canvas.correction_strength,.72),"Switching image workspaces restores correction settings")
	if DisplayServer.get_name()!="headless":
		var path: String="user://stroke_settings_"+ActorData.new_id()+".tres"
		studio._persist_paint_presets(path); studio.canvas.stroke_correct=false; studio.canvas.correction_strength=.1
		studio._load_paint_presets(path)
		check(studio.canvas.stroke_correct and is_equal_approx(studio.canvas.correction_strength,.72),"Reopening the editor restores saved correction preferences")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if OS.get_cmdline_user_args().has("--visual"):
		studio.canvas.tool="brush"; studio._refresh_context()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/stroke_correct_ui.png")
	studio.free(); await process_frame
	print("Corrected paint checks: %d failures" % failures); quit(failures)

func check_actual_input(settings: SettingsStudio) -> void:
	var outline:=PackedVector2Array()
	for i in 601:
		var angle:=float(i)/600*TAU
		var noise:=sin(angle*19)*4.0+sin(angle*61)*1.0
		outline.append(Vector2(225,210)+Vector2(cos(angle)*(155+noise),sin(angle)*(160+noise)))
	var outputs: Array[Image]=[]
	for enabled in [false,true]:
		settings.document=KiwiImageDocument.new(); settings.document.canvas_size=Vector2i(450,420)
		var layer:=KiwiImageLayer.create("basic",settings.document.canvas_size); settings.document.layers.append(layer)
		settings.canvas.document=settings.document; settings.canvas.selected.assign([layer.id])
		settings.canvas.tool="brush"; settings.canvas.color=Color.BLACK
		settings.canvas.brush_size=3; settings.canvas.brush_opacity=1; settings.canvas.hardness=1
		settings.canvas.zoom=1; settings.canvas.pan=Vector2.ZERO
		settings.canvas.stroke_correct=not enabled; settings._refresh_context()
		(settings.context.find_child("BrushType",true,false) as MenuButton).get_popup().id_pressed.emit(1 if enabled else 0)
		(settings.context.find_child("CorrectionStrength",true,false) as HSlider).value=100
		var down:=InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true
		down.position=settings.canvas.origin()+outline[0]
		settings.canvas._input_canvas(down)
		check((settings.canvas._corrector!=null)==enabled,"Actual toolbar toggle controls the mouse-input correction path")
		for i in range(1,outline.size()):
			var motion:=InputEventMouseMotion.new(); motion.position=settings.canvas.origin()+outline[i]; motion.button_mask=MOUSE_BUTTON_MASK_LEFT
			settings.canvas._input_canvas(motion)
			if i%4==0: settings.canvas._process(1.0/60)
		var up:=InputEventMouseButton.new(); up.button_index=MOUSE_BUTTON_LEFT; up.position=settings.canvas.origin()+outline[-1]
		settings.canvas._input_canvas(up)
		outputs.append(layer.texture.get_image())
	check(outputs[0].get_data()!=outputs[1].get_data(),"Identical mouse movements produce visibly different corrected pixels")
	var comparison:=Image.create(910,420,false,Image.FORMAT_RGBA8)
	for y in comparison.get_height():
		for x in comparison.get_width(): comparison.set_pixel(x,y,Color("34414f") if (x/24+y/24)%2==0 else Color("293541"))
	comparison.blend_rect(outputs[0],Rect2i(Vector2i.ZERO,outputs[0].get_size()),Vector2i.ZERO)
	comparison.blend_rect(outputs[1],Rect2i(Vector2i.ZERO,outputs[1].get_size()),Vector2i(460,0))
	comparison.save_png("res://.godot/stroke_correction_comparison_v3.png")
