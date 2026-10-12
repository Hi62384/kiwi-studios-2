extends SceneTree
class TestStudio extends KiwiImageWorkspace:
	func _persist_paint_presets(_path: String=PAINT_PRESETS_PATH) -> void: pass
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func run() -> void:
	root.size=Vector2i(1400,850); root.gui_embed_subwindows=true
	var studio:=TestStudio.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source:=Image.create(64,64,false,Image.FORMAT_RGBA8); source.fill(Color.RED); source.fill_rect(Rect2i(32,0,32,64),Color.BLUE)
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("brush")
	var types:=studio.find_child("BrushType",true,false) as MenuButton
	check(types!=null and types.get_popup().item_count==4,"Brush types use the styled three-choice menu")
	check(studio.find_child("StrokeCorrect",true,false)==null,"Stroke Correct is no longer a checkbox")
	types.get_popup().id_pressed.emit(2)
	check(studio.canvas.brush_type=="soften" and not studio.canvas.stroke_correct,"Menu selects Soften without enabling stroke correction")
	check(studio.find_child("SoftenStrength",true,false)!=null,"Soften shows its strength control")
	studio.canvas.soften_strength=1; studio.canvas.brush_size=24; studio.canvas.hardness=1; studio.canvas.brush_opacity=1; studio.canvas.color=Color.GREEN
	studio.canvas._begin_paint(Vector2(32,32))
	var image:=studio._main_layer().texture.get_image(); var edge:=image.get_pixel(31,32)
	check(edge.r>.1 and edge.b>.1 and edge.g<.01,"Soften blends neighboring colors without painting the selected brush color")
	check(image.get_pixel(4,4)==Color.RED,"Soften does not change pixels outside its brush")
	var before:=image.get_data()
	for i in 4: studio.canvas._paint_line(Vector2(32,32),Vector2(32,32))
	check(studio._main_layer().texture.get_image().get_data()==before,"Repeated dabs use the fixed stroke snapshot rather than accumulating opacity")
	studio.canvas._finish(Vector2(32,32)); check(studio._undo.size()==1,"Soften creates one undo entry per gesture")
	studio.undo(); check(studio._main_layer().texture.get_image().get_data()==source.get_data(),"Soften supports undo")
	studio.redo(); check(studio._main_layer().texture.get_image().get_pixel(31,32).b>.1,"Soften supports redo")
	studio.undo(); studio.canvas.soften_strength=0; studio.canvas._begin_paint(Vector2(32,32))
	check(studio._main_layer().texture.get_image().get_data()==source.get_data(),"Zero soften strength preserves the source")
	studio.canvas.cancel_gesture(); studio.canvas.soften_strength=1
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(24,24,16,16),Color(1,1,1,.5))
	studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=studio._main_layer().id; studio.canvas.sync_pixel_selection(); studio.canvas.paint_selection_only=true
	studio.canvas._begin_paint(Vector2(32,32)); edge=studio._main_layer().texture.get_image().get_pixel(31,32)
	check(edge.b>0 and edge.b<image.get_pixel(31,32).b*.6,"Soften respects fractional selection coverage")
	studio.canvas.cancel_gesture()
	var preset:=studio._current_paint_preset("Soften")
	check(preset.brush_type=="soften" and preset.soften_strength==1,"Brush presets preserve type and soften strength")
	var state:=studio.capture_state(); studio.canvas.brush_type="normal"; studio.open_source(null,state)
	check(studio.canvas.brush_type=="soften","Workspace state preserves the selected brush type")
	var prepare=preload("res://Workspaces/ImageWorkspace/image_soften_brush.gd")
	var transparent:=Image.create(32,32,false,Image.FORMAT_RGBA8); transparent.fill_rect(Rect2i(0,0,16,32),Color.WHITE)
	var filtered: Image=prepare.prepare(transparent,4)
	var p:=filtered.get_pixel(15,16)
	check(p.a>0 and absf(p.r/p.a-1)<.02,"Soften filtering preserves color around transparent edges")
	var all:=Image.create(32,32,false,Image.FORMAT_RGBA8); all.fill(Color.WHITE)
	var mixed: Image=prepare.composite(transparent,filtered,all,Rect2i(0,0,32,32),.5,1)
	check(mixed.get_pixel(16,16).a>0 and mixed.get_pixel(16,16).r>.98,"Partial soften strength does not darken newly softened transparent edges")
	studio.canvas.paint_selection_only=false; studio._refresh_context()
	for i in 5: await process_frame
	types=studio.find_child("BrushType",true,false) as MenuButton
	types.get_popup().position=Vector2i(types.global_position+Vector2(0,types.size.y)); types.get_popup().popup()
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("res://.godot/brush_type_menu_ui.png")
	types.get_popup().hide()
	studio._action(func(): studio._main_layer().effects=[studio._new_effect("emboss")])
	studio._open_stack_editor(false)
	var editor:=studio.get_node("EffectStackEditor"); var preserve: CheckButton
	for node in editor.find_children("*","CheckButton",true,false):
		if node.text=="Preserve color": preserve=node
	check(preserve!=null,"Emboss exposes its Preserve Color option")
	if preserve!=null:
		preserve.button_pressed=true
		check(studio._main_layer().effects[0].get("preserve_color",false),"Emboss Preserve Color UI updates the effect")
		studio.undo(); check(not studio._main_layer().effects[0].get("preserve_color",false),"Emboss Preserve Color supports undo")
		studio.redo(); check(studio._main_layer().effects[0].get("preserve_color",false),"Emboss Preserve Color supports redo")
	editor.close_editor()
	studio.queue_free(); for i in 5: await process_frame
	print("Brush types / Soften checks: %d failures" % failures); quit(failures)
