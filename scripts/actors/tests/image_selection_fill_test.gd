extends SceneTree
var failures:=0
func _initialize() -> void: execute.call_deferred()
func execute() -> void:
	await run()
	for frame in 10: await process_frame
	quit(failures)
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func run() -> void:
	root.size=Vector2i(1200,800)
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source:=Image.create(64,64,false,Image.FORMAT_RGBA8); source.fill(Color.BLUE)
	studio.open_source(ImageTexture.create_from_image(source)); studio._set_tool("pixel_select")
	var layer:=studio._main_layer(); layer.position=Vector2(8,4); layer.rotation=.2
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(18,18,20,20),Color.WHITE)
	studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=layer.id
	studio.canvas.sync_pixel_selection()
	await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").apply(studio,Color.RED)
	var result:=studio._main_layer().texture.get_image()
	var inside:=Vector2i(studio.document.world_transform(studio._main_layer()).affine_inverse()*Vector2(28,28))
	check(result.get_pixelv(inside).r>.95 and result.get_pixelv(inside).b<.05,"Color fill affects selected pixels through the layer transform")
	check(result.get_pixel(55,55).b>.95,"Color fill preserves unselected pixels")
	check(studio._undo.size()==1,"Color fill creates one undo entry")
	studio.undo(); check(studio._main_layer().texture.get_image().get_pixelv(inside).b>.95,"Color fill supports undo")
	studio.redo(); check(studio._main_layer().texture.get_image().get_pixelv(inside).r>.95,"Color fill supports redo")
	var math=preload("res://Workspaces/ImageWorkspace/image_values.gd")
	var lerp:=math.new_operation("lerp"); lerp.b={"kind":"vector","channels":[1.0,0.0,0.0,1.0]}; lerp.c.value=.5
	var actual: Vector3=math.evaluate(Vector3(0,0,1),[lerp])
	check(actual.distance_to(Vector3(.5,0,.5))<.001,"Lerp blends toward a chosen color rather than a gray scalar")
	studio._set_tool("values"); studio._open_stack_editor(true)
	var editor:=studio.get_node("AdjustmentStackEditor"); editor.add_entry("lerp")
	check(not editor.stack.find_children("*","ColorPickerButton",true,false).is_empty(),"Lerp exposes a target color picker")
	editor.close_editor()
	# Drain asynchronous selection captures before their viewport owners die.
	for frame in 24: await RenderingServer.frame_post_draw
	studio.color_picker.queue_free(); studio.queue_free()
	for i in 5: await process_frame
	await fractional()
	print("Selection fill / color lerp checks: %d failures" % failures)

func fractional() -> void:
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio); studio.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var source:=Image.create(32,32,false,Image.FORMAT_RGBA8); source.fill(Color.BLUE)
	studio.open_source(ImageTexture.create_from_image(source))
	var layer:=studio._main_layer()
	var mask:=Image.create(32,32,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(4,4,24,24),Color(1,1,1,.5))
	studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=layer.id; studio.canvas.sync_pixel_selection()
	await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").apply(studio,Color.RED)
	var pixel:=studio._main_layer().texture.get_image().get_pixel(16,16)
	check(absf(pixel.r-.5)<.02 and absf(pixel.b-.5)<.02,"GPU Color Fill blends half-selected pixels by half")
	studio.undo()
	await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").apply(studio,Color(1,0,0,.5))
	pixel=studio._main_layer().texture.get_image().get_pixel(16,16)
	check(absf(pixel.r-.25)<.02 and absf(pixel.b-.75)<.02 and pixel.a>.99,"Fill color alpha multiplies selection alpha without replacing opaque pixels with translucent ones")
	studio.undo()
	await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").apply(studio,Color(1,0,0,0))
	check(studio._main_layer().texture.get_image().get_data()==source.get_data(),"A fully transparent fill color leaves original pixels unchanged")
	studio.undo(); studio.canvas.brush_type="normal"; studio._set_tool("brush")
	studio.canvas.paint_selection_only=true; studio.canvas.color=Color.RED; studio.canvas.brush_opacity=1; studio.canvas.brush_size=12; studio.canvas.hardness=1; studio.canvas.stroke_correct=false
	studio.canvas._begin_paint(Vector2(16,16))
	for i in 5: studio.canvas._paint_line(Vector2(16,16),Vector2(16,16))
	pixel=studio._main_layer().texture.get_image().get_pixel(16,16)
	check(absf(pixel.r-.5)<.02 and absf(pixel.b-.5)<.02,"Repeated brush dabs retain fractional-selection coverage for the entire gesture")
	studio.canvas._finish(Vector2(16,16)); studio.undo(); studio._set_tool("eraser")
	studio.canvas._begin_paint(Vector2(16,16))
	for i in 5: studio.canvas._paint_line(Vector2(16,16),Vector2(16,16))
	pixel=studio._main_layer().texture.get_image().get_pixel(16,16)
	check(absf(pixel.a-.5)<.02,"Repeated eraser dabs cannot exceed half-selection coverage")
	studio.canvas._finish(Vector2(16,16)); studio.undo(); studio._set_tool("fill"); studio.canvas.color=Color.RED
	studio.canvas._begin_paint(Vector2(16,16)); pixel=studio._main_layer().texture.get_image().get_pixel(16,16)
	check(absf(pixel.r-.5)<.02 and absf(pixel.b-.5)<.02,"Bucket fill honors selection alpha")
	studio.undo(); layer=studio._main_layer()
	layer.properties.value_operations=[{"type":"lerp","a":{"kind":"pixel"},"b":{"kind":"vector","channels":[1.0,0.0,0.0,1.0]},"c":{"kind":"float","value":1.0},"enabled":true}]
	layer.properties.values_selection_only=true; layer.properties.values_selection=studio.document.pixel_selection; layer.properties.values_selection_frame=Transform2D.IDENTITY; layer.properties.values_selection_dimensions=layer.dimensions
	studio.renderer.sync(studio.document); var adjusted: Image=await studio.renderer.flattened(); pixel=adjusted.get_pixel(16,16)
	check(absf(pixel.r-.5)<.03 and absf(pixel.b-.5)<.03,"Adjustments lerp their result by selection alpha")
	# Exercise the real toolbar toggle after the selected layer has moved,
	# resized and acquired yaw. The mask still lives in its original coordinates.
	studio.document.pixel_selection_reference=layer.copy_layer(); studio.document.pixel_selection_reference_world=studio.document.world_transform(layer)
	layer.position=Vector2(80,40); layer.dimensions=Vector2(64,48); layer.rotation=.2; layer.properties.yaw_left_right=30.0
	studio.canvas.sync_pixel_selection(); studio._set_tool("values")
	await studio._set_adjustment_selection_only(true)
	check(layer.properties.get("values_selection_local",false) and layer.properties.values_selection!=null,"Toolbar captures a valid local adjustment mask from transformed selections")
	studio.renderer.sync(studio.document)
	for i in 12: await RenderingServer.frame_post_draw
	var surface: Image=studio.renderer.views[layer.id].stages[-2].viewport.get_texture().get_image()
	pixel=surface.get_pixel(48+32,48+24)
	check(absf(pixel.r-.5)<.04 and absf(pixel.b-.5)<.04,"Selected-only adjustments remain visible inside a moved, scaled, rotated and yawed layer")
	check(surface.get_pixel(49,49).b>.95 and surface.get_pixel(49,49).r<.05,"Selected-only adjustments preserve unselected pixels")
	studio.undo(); check(not studio._main_layer().properties.get("values_selection_local",false),"Adjustment selection toggle supports undo")
	studio.redo(); layer=studio._main_layer(); check(layer.properties.get("values_selection_local",false),"Adjustment selection toggle supports redo")
	layer.position=Vector2.ZERO; layer.dimensions=Vector2(32,32); layer.rotation=0; layer.properties.yaw_left_right=0
	layer.properties.value_operations=[]
	layer.properties.effects_selection_only=true; layer.properties.effects_selection=studio.document.pixel_selection; layer.properties.effects_selection_frame=Transform2D.IDENTITY; layer.properties.effects_selection_dimensions=layer.dimensions
	layer.effects=[{"type":"invert","enabled":true,"amount":1.0}]
	studio.renderer.sync(studio.document); adjusted=await studio.renderer.flattened(); pixel=adjusted.get_pixel(16,16)
	check(absf(pixel.r-.5)<.03 and absf(pixel.g-.5)<.03 and absf(pixel.b-.5)<.03,"Effects lerp their result by selection alpha")
	# Selection undo/redo can still have a source capture awaiting rendered frames.
	for frame in 24: await RenderingServer.frame_post_draw
	# Release the legacy unparented color-state control owned by this fixture.
	studio.color_picker.queue_free(); studio.queue_free()
	for i in 6: await process_frame
