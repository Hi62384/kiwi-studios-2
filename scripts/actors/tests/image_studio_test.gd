extends SceneTree
## Model and real-renderer coverage. -- --visual also writes a UI screenshot.

const Studio = preload("res://Workspaces/ImageWorkspace/image_workspace.gd")
var failures := 0

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void:
	run.call_deferred()

func check_value_adjustments(studio: Control) -> void:
	var math_script=preload("res://Workspaces/ImageWorkspace/image_values.gd")
	var subtract: Dictionary=math_script.new_operation("subtract")
	subtract.a={"kind":"float","value":1.0}; subtract.b={"kind":"pixel"}
	var inverted: Vector4=math_script.evaluate_rgba(Vector4(.2,.4,.8,.7),[subtract])
	check(inverted.is_equal_approx(Vector4(.8,.6,.2,.7)),"Swapped operands invert RGB without removing alpha")
	var multiply: Dictionary=math_script.new_operation("multiply")
	multiply.b={"kind":"vector","channels":[10.0,"g",1.0,"a"]}
	check(math_script.evaluate_rgba(Vector4(.05,.4,.8,.7),[multiply]).is_equal_approx(Vector4(.5,.16,.8,.7)),"Vector operands mix constants and per-channel pixel references")
	var snap: Dictionary=math_script.new_operation("snap")
	snap.b.value=.25
	var snapped: Vector4=math_script.evaluate_rgba(Vector4(.63,.315,.126,1),[snap])
	check(is_equal_approx(snapped.y/snapped.x,.5) and is_equal_approx(snapped.z/snapped.x,.2),"Hue-preserving snap retains channel ratios")
	var layer: KiwiImageLayer=studio.document.layers[0]
	studio.canvas.selected.assign([layer.id])
	studio._action(func():
		layer.properties.value_operations=[{"type":"hue","amount":TAU/3.0}]
		layer.properties.value_basics={"brightness":.05})
	var ops: Array=math_script.operations(layer)
	check(ops.back().type=="brightness","Basic color adjustments execute last")
	var wanted:=Color(.75,.2,.3)
	var source: Color=math_script.inverse_color(wanted,layer)
	check(math_script.evaluate(Vector3(source.r,source.g,source.b),ops).distance_to(Vector3(wanted.r,wanted.g,wanted.b))<.01,"Painting inverses hue and brightness")
	check(layer.copy_layer().properties.value_operations.size()==1,"Operation stack survives snapshots")
	studio.undo(); check(not studio.document.layers[0].properties.has("value_operations"),"Adjustments undo")
	studio.redo(); layer=studio.document.layers[0]
	check(layer.properties.value_operations.size()==1,"Adjustments redo")
	if DisplayServer.get_name()!="headless":
		var bitmap:=Image.create(32,32,false,Image.FORMAT_RGBA8); bitmap.fill(Color(.2,.3,.4))
		layer.texture=ImageTexture.create_from_image(bitmap)
		layer.properties.value_operations=[{"type":"multiply","amount":2.0}]
		layer.properties.value_basics={"brightness":.1}
		studio.renderer.sync(studio.document)
		var rendered: Image=await studio.renderer.flattened()
		var sample:=rendered.get_pixel(rendered.get_width()/2,rendered.get_height()/2)
		check(absf(sample.r-.5)<.035 and absf(sample.b-.9)<.035,"GPU applies ordered operations before basic adjustments")
	for type in math_script.TYPES:
		layer.properties.value_operations.append(math_script.new_operation(type))
	layer.properties.value_operations.append(multiply)
	layer.properties.value_operations.append(subtract)
	layer.properties.value_basics={"temperature":-.2,"tint":.1,"gamma":1.2,"exposure":.5}
	studio.renderer.sync(studio.document)
	await process_frame
	studio._set_tool("values")
	studio._open_values(true)
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://image_values_ui.png")
	for child in studio.get_children():
		if child is Window and child.title.begins_with("Order edit"):
			check(child.position.y>=0 and child.position.y+child.size.y<=root.size.y,"Operation window fits inside the screen")
			var preview: Control=child.get_child(0).get_child(0).get_child(0)
			var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.position=preview.size*.5
			preview._gui_input(wheel)
			check(preview.zoom>1,"Operation preview supports wheel zoom")
			var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; preview._gui_input(press)
			var motion:=InputEventMouseMotion.new(); motion.relative=Vector2(20,30); preview._gui_input(motion)
			check(preview.pan.is_equal_approx(Vector2(20,30)),"Operation preview supports drag panning")
			child.close_requested.emit()
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://image_value_sliders_ui.png")
	studio._set_tool("move")

func run() -> void:
	root.size=Vector2i(1440,900)
	var studio:=Studio.new()
	root.add_child(studio)
	await process_frame
	studio.open_source(null)
	await check_value_adjustments(studio)
	studio.open_source(null)
	check(studio.document.layers.size()==1 and studio.document.layers[0].kind=="basic","A new Image Studio tab starts with a Basic layer")
	var original_brush_size:=studio.canvas.brush_size
	studio.canvas.tool="brush"
	var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.ctrl_pressed=true; wheel.position=Vector2(20,20)
	studio.canvas._input_canvas(wheel)
	check(studio.canvas.brush_size>original_brush_size and is_equal_approx(studio.canvas.zoom,.7),"Ctrl+wheel changes brush size without zooming the canvas")
	studio._apply_paint_preset("brush",studio._paint_presets.brush[0]); studio.canvas.brush_size=41; studio._save_paint_preset("brush",false)
	check(is_equal_approx(float(studio._paint_presets.brush[0].size),41),"Save updates the selected brush preset")
	var preset_count: int=studio._paint_presets.brush.size()
	studio._save_paint_preset("brush",true); await process_frame
	check(studio._paint_presets.brush.size()==preset_count+1,"Save as new creates a preset immediately")
	var new_preset_id: String=studio._paint_presets.brush.back().id
	studio._move_preset("brush",new_preset_id,studio._paint_presets.brush[0].id)
	check(studio._paint_presets.brush[0].id==new_preset_id,"Dragging presets reorders keyboard slots")
	var spans:=studio._crop_spans(Rect2i(0,0,20,20),PackedVector2Array([Vector2(0,0),Vector2(20,0),Vector2(0,20)]))
	check(spans.size()==19 and spans[0].size.x>spans.back().size.x,"Lasso crop fills the interior with bounded scanline spans")
	studio.canvas._points=PackedVector2Array([Vector2(5,5),Vector2(30,5),Vector2(30,30),Vector2(5,30)])
	studio.canvas._make_selection("lasso",Rect2(5,5,25,25))
	check(studio.canvas.selected_pixel(Vector2(10,10)) and not studio.canvas.selected_pixel(Vector2(2,2)) and studio.canvas.pixel_selection_bounds.size==Vector2(25,25),"Lasso selection creates a bounded pixel mask instead of covering the viewport")
	studio.canvas.clear_selection()
	studio.canvas._stroke_points=PackedVector2Array([Vector2(0,0),Vector2(50,45),Vector2(100,0)])
	check(studio.canvas._curve_control(Vector2(0,0),Vector2(100,0)).y>40,"Curve gestures derive an obvious bend from the drawn guide path")
	var noise_layer:=studio.add_layer("noise")
	check(noise_layer.properties.get("noise_object") is ActorObjectData and (noise_layer.properties.noise_object as ActorObjectData).type_id==&"noise_image" and noise_layer.texture!=null,"Noise layers use an editable Noise Image object")
	var bitmap:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	bitmap.fill(Color.RED)
	studio.open_source(bitmap)
	var background_id: String=studio.document.layers[0].id
	studio.canvas.selected.assign([background_id])
	studio._action(func(): studio._set_common("width",-64.0))
	check(studio.document.layers[0].dimensions.x==64 and studio.document.layers[0].properties.get("flip_x",false),"A negative layer width flips it without creating invalid render dimensions")
	studio.undo()
	studio._create_noise_image(studio.document.layers[0])
	check(studio.document.layers[0].properties.get("noise_image") is Dictionary and studio.document.layers[0].texture!=null,"Image layers can create an editable procedural noise image source")
	studio.undo()
	var shape:=studio.add_layer("shape")
	shape.position=Vector2(16,16); shape.dimensions=Vector2(32,32)
	shape.properties.color=Color.GREEN; shape.properties.radius=0
	studio.canvas.selected.assign([shape.id,background_id]); studio.parent_selected()
	check(studio.document.layer_for_id(shape.id).parent_id==background_id,"Any layer can be parented under another layer")
	studio.canvas.selected.assign([shape.id]); studio.unparent_selected()
	check(studio.document.layer_for_id(shape.id).parent_id.is_empty(),"Layer unparent restores a root layer")
	studio._preview()
	studio.canvas.selected.assign([background_id,shape.id])
	studio.group_selected()
	var group:=studio._main_layer()
	check(group.kind=="group" and studio.document.children(group.id).size()==2,"Grouping preserves the editable child layers")
	var group_id:=group.id
	studio.undo()
	check(studio.document.layer_for_id(group_id)==null and studio.document.children().size()==2,"Group undo restores the original hierarchy")
	studio.redo()
	check(studio.document.children(group_id).size()==2,"Group redo restores children")
	studio.ungroup_selected()
	# Undo/redo deliberately keeps selection by stable IDs; select the group explicitly.
	if studio.document.layer_for_id(group_id)!=null:
		studio.canvas.selected.assign([group_id]); studio.ungroup_selected()
	check(studio.document.children().size()==2,"Ungroup preserves child content")
	var capture:=studio.capture_state()
	studio.open_source(null,capture)
	check(studio._undo.size()>0 and studio.document.layers.size()==2,"Tab state retains both composition and undo history")
	var native_path: String="user://image_studio_roundtrip.tres"
	check(ResourceSaver.save(studio.document,native_path)==OK,"Native composition can be serialized")
	var restored:=ResourceLoader.load(native_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(restored!=null and restored.layers.size()==2 and restored.layers[0].texture!=null,"Native composition restores raster and editable shape layers")
	studio.canvas.selected.assign([background_id]); studio.canvas.tool="brush"; studio.canvas.color=Color.BLUE; studio.canvas.brush_size=2
	studio.canvas._begin_paint(Vector2(3,3)); studio.canvas._finish(Vector2(3,3))
	check(studio.document.layer_for_id(background_id).texture.get_image().get_pixel(3,3).b>.9,"Brush gesture paints the selected layer")
	studio.undo()
	check(studio.document.layer_for_id(background_id).texture.get_image().get_pixel(3,3).r>.9,"Brush undo preserves immutable source pixels")
	studio.canvas.paint_new_layer=true; studio.canvas.selected.assign([background_id]); var before_stroke_layers:=studio.document.layers.size()
	studio.canvas._begin_paint(Vector2(8,8)); studio.canvas._finish(Vector2(8,8))
	check(studio.document.layers.size()==before_stroke_layers+1 and studio._main_layer().kind=="basic","New-layer painting creates one Basic layer for the completed stroke")
	var stroke_bitmap:=studio._main_layer().texture.get_image()
	var stroke_pixel:=stroke_bitmap.get_pixel(0,0)
	check(studio._main_layer().dimensions==Vector2(stroke_bitmap.get_size()) and studio._main_layer().dimensions.x<64 and stroke_pixel.b>.9 and stroke_pixel.r<.1,"A new-layer stroke is tightly bounded and never exposes white transparent pixels")
	check(studio.canvas.hit(studio._main_layer().position+studio._main_layer().dimensions*.5)==studio._main_layer(),"Selected sparse layers can be moved by dragging anywhere inside their bounds")
	studio.undo(); check(studio.document.layers.size()==before_stroke_layers,"A generated stroke layer and its pixels undo as one action"); studio.canvas.paint_new_layer=false
	studio.canvas.selected.assign([background_id]); studio.canvas.color=Color.GREEN
	studio.canvas._begin_paint(Vector2(4,4)); studio.canvas._finish(Vector2(4,4)); studio.restore_layer_paint()
	check(studio.document.layer_for_id(background_id).texture.get_image().get_pixel(4,4).r>.9,"Restore removes all painting and erasing from a raster layer")
	studio.canvas.selected.assign([background_id]); studio._action(func(): studio.document.layer_for_id(background_id).dimensions=Vector2(20,20)); studio.fill_selected_to_parent()
	check(studio.document.layer_for_id(background_id).position==Vector2.ZERO and studio.document.layer_for_id(background_id).dimensions==Vector2(64,64),"Fill sizes a root layer to the full canvas")
	if DisplayServer.get_name()!="headless":
		var rendering_fixture:=studio.capture_state()
		var yaw_source:=Image.create(96,96,false,Image.FORMAT_RGBA8); yaw_source.fill(Color.WHITE)
		for axis in ["yaw_up_down","yaw_left_right"]:
			studio.open_source(yaw_source); studio.document.layers[0].properties[axis]=45.0
			studio.renderer.sync(studio.document)
			var projected:=await studio.renderer.flattened()
			var first_half:=0.0; var second_half:=0.0
			for y in 96:
				for x in 96:
					if (y if axis=="yaw_up_down" else x)<48: first_half+=projected.get_pixel(x,y).a
					else: second_half+=projected.get_pixel(x,y).a
			check(absf(first_half-second_half)>100,"A single yaw axis produces perspective, not symmetric scaling")
		var source_bitmap:=Image.create(16,16,false,Image.FORMAT_RGBA8); source_bitmap.fill(Color.RED)
		source_bitmap.save_png("user://image_save_source.png")
		studio.open_source("user://image_save_source.png")
		var replacement:=Image.create(16,16,false,Image.FORMAT_RGBA8); replacement.fill(Color.BLUE)
		studio.document.layers[0].texture=ImageTexture.create_from_image(replacement)
		await studio.save_image()
		check(Image.load_from_file("user://image_save_source.png").get_pixel(8,8).b>.95,"Save image overwrites the original image path")
		check(studio.document_path.is_empty(),"Saving an image does not create a sidecar project")
		studio.document_path="user://image_save_project.tres"
		await studio.save_project()
		var saved_project:=ResourceLoader.load(studio.document_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
		check(saved_project!=null and saved_project.layers.size()==1 and saved_project.output_path=="user://image_save_source.png","Save project preserves layers and the independently linked image destination")
		check(saved_project.layers[0].texture is PortableCompressedTexture2D,"Projects store embedded raster data losslessly compressed")
		await studio._export_to("user://image_export.png")
		check(FileAccess.file_exists("user://image_export.png") and studio.document.output_path=="user://image_save_source.png","Export does not replace the linked image destination")
		studio.open_source(null,rendering_fixture)
		studio.renderer.sync(studio.document)
		var rendered:=await studio.renderer.flattened()
		check(rendered!=null and rendered.get_width()==64,"GPU output matches document dimensions")
		if rendered!=null:
			check(rendered.get_pixel(2,2).r>.9,"Image layer appears in the composition")
			check(rendered.get_pixel(30,30).g>.9,"Shape layer composites above the image")
		studio.canvas.selected.assign([background_id]); studio.canvas.tool="move"; studio.canvas.snapping=false; studio._refresh_context()
		studio.canvas._bounds=studio.canvas.selection_bounds(); studio.canvas._start=Vector2.ZERO; studio.canvas._begin_transform("move")
		studio.canvas._transform(Vector2(5,3),false,false)
		check(studio.document.layer_for_id(background_id).position==Vector2(5,3) and is_equal_approx(studio._context_fields.x.value,5),"Viewport movement updates the layer and top transform strip live")
		studio.canvas.cancel_gesture()
		studio.canvas.selected.assign([background_id]); studio._refresh_context(); studio.renderer.sync(studio.document)
		studio.canvas._bounds=studio.canvas.selection_bounds(); studio.canvas._start=studio.canvas._bounds.end; studio.canvas._begin_transform("resize4")
		studio.canvas._transform(studio.canvas._start+Vector2(12,12),false,false)
		var live_output:=studio.renderer.views[background_id].output as Sprite2D
		check(live_output.scale.x>1.0 and live_output.position.is_equal_approx(-Vector2.ONE*studio.renderer.PAD*live_output.scale) and studio._context_fields.width.value>64,"Viewport resizing keeps actual pixels aligned to the live bounding box and updates the top strip")
		studio.canvas._finish(studio.canvas._start+Vector2(12,12)); studio.renderer.sync(studio.document)
		var committed_output:=studio.renderer.views[background_id].output as Sprite2D
		check(committed_output.scale==Vector2.ONE and committed_output.position==-Vector2.ONE*studio.renderer.PAD,"Committed resizing preserves the same padded pixel origin as its bounding box")
		studio.undo()
		for handle in studio.canvas._handles(Rect2(Vector2(-500,-500),Vector2(2000,1600))):
			check(Rect2(Vector2.ZERO,studio.canvas.size).has_point(handle),"Oversized layers keep resize handles inside the viewport")
		studio.select_all(); studio.group_selected(); studio.group_selected()
		studio.renderer.sync(studio.document)
		var nested:=await studio.renderer.flattened()
		check(nested.get_pixel(2,2).r>.9 and nested.get_pixel(30,30).g>.9,"Nested groups preserve layer placement and compositing")
		studio.undo(); studio.undo()
		studio.path="user://image_studio_output.png"; studio.source=studio.path
		studio.document.output_path=studio.path
		studio.document_path="user://image_studio_output.tres"
		await studio.save()
		check(FileAccess.file_exists(studio.document.output_path) and FileAccess.file_exists(studio.document_path),"Overall Save writes both linked image and project")
		studio.open_source(studio.document_path)
		check(studio.document.layers.size()==2,"Reopening the project restores its editable composition")
		studio.select_all(); await studio.merge_selected()
		check(studio.document.layers.size()==1 and studio.document.layers[0].kind=="basic","Merge bakes selected content into one directly editable basic layer")
		studio.undo()
		studio.canvas.selected.assign([studio.document.layers[0].id]); studio._crop_action=1
		await studio._apply_crop(Rect2(8,8,24,20))
		var crop_layer:=studio._main_layer()
		check(crop_layer.kind=="basic" and crop_layer.dimensions==Vector2(24,20) and studio.document.layers.size()==3,"Non-destructive crop copies a region into a new layer")
		studio.undo()
		var editable_text:=studio.add_layer("text"); studio.canvas.selected.assign([editable_text.id])
		await studio.rasterize_selected()
		check(studio._main_layer().kind=="basic","Text and other procedural layers can be converted for direct brush and eraser editing")
		var asymmetric:=Image.create(4,2,false,Image.FORMAT_RGBA8); asymmetric.fill(Color.RED); asymmetric.fill_rect(Rect2i(2,0,2,2),Color.BLUE)
		studio.open_source(asymmetric); studio._action(func(): studio._set_common("width",-4.0)); studio.renderer.sync(studio.document)
		var flipped:=await studio.renderer.flattened()
		check(flipped.get_pixel(0,0).b>.9 and flipped.get_pixel(3,0).r>.9,"Negative dimensions render as a clean horizontal layer flip")
		var translucent:=Image.create(8,8,false,Image.FORMAT_RGBA8)
		translucent.fill(Color(1,0,0,.5))
		studio.open_source(translucent)
		var alpha_render:=await studio.renderer.flattened()
		if alpha_render!=null:
			check(alpha_render.get_pixel(4,4).r>.95 and absf(alpha_render.get_pixel(4,4).a-.5)<.03,"Transparent layers preserve color and alpha through rendering")
		studio.add_effect("brightness")
		studio.document.layers[0].effects[0].amount=.2
		studio.renderer.sync(studio.document)
		var adjusted:=await studio.renderer.flattened()
		check(adjusted.get_pixel(4,4).g>.17 and adjusted.get_pixel(4,4).g<.23,"Effect stack changes straight color without darkening transparent pixels")
		var mask:=Image.create(8,8,false,Image.FORMAT_RGBA8); mask.fill(Color.BLACK); mask.fill_rect(Rect2i(0,0,4,8),Color.WHITE)
		studio.document.layers[0].mask=ImageTexture.create_from_image(mask)
		studio.renderer.sync(studio.document)
		var masked:=await studio.renderer.flattened()
		check(masked.get_pixel(6,4).a<.01 and masked.get_pixel(2,4).a>.45,"Layer mask controls output alpha")
		var clipped:=studio.add_layer("shape"); clipped.dimensions=Vector2(8,8); clipped.position=Vector2.ZERO; clipped.properties.color=Color.GREEN; clipped.properties.radius=0; clipped.clip_to_below=true
		studio.renderer.sync(studio.document)
		var clipped_image:=await studio.renderer.flattened()
		check(clipped_image.get_pixel(6,4).a<.01 and clipped_image.get_pixel(2,4).g>.4,"Clipping uses the transformed layer below as its alpha boundary")
		studio.open_source(translucent)
		var shader:=Shader.new(); shader.code="shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV); COLOR.rgb = vec3(1.0) - COLOR.rgb; }"
		studio.document.layers[0].effects.append({"id":"test_shader","type":"shader","enabled":true,"shader":shader,"uniforms":{}})
		studio.renderer.sync(studio.document)
		var shader_image:=await studio.renderer.flattened()
		check(shader_image.get_pixel(4,4).g>.95 and shader_image.get_pixel(4,4).r<.02 and absf(shader_image.get_pixel(4,4).a-.5)<.03,"Canvas shader effects receive straight image color and preserve transparency")
		studio.add_effect("curves")
		studio.renderer.sync(studio.document)
		var curves_image:=await studio.renderer.flattened()
		check(curves_image.get_pixel(4,4).g>.9,"Default color curve is an identity mapping")
		var noise:=studio.add_layer("noise"); noise.dimensions=Vector2(64,64); noise.properties.noise_seed=123
		studio.renderer.sync(studio.document)
		for frame in 8: await process_frame
		var noise_image:=await studio.renderer.flattened()
		check(noise_image!=null and not noise_image.is_empty(),"Procedural noise layer renders without changing the source model")
		if OS.get_cmdline_user_args().has("--visual"):
			studio.open_source(null)
			studio.document.layers.clear()
			var gradient:=studio.add_layer("gradient"); gradient.properties.color=Color("172849"); gradient.properties.color_end=Color("47706b"); gradient.properties.gradient_angle=28.0
			var card:=studio.add_layer("shape"); card.position=Vector2(120,120); card.dimensions=Vector2(1040,480); card.properties.color=Color("142235"); card.properties.radius=42
			var circle:=studio.add_layer("shape"); circle.position=Vector2(810,165); circle.dimensions=Vector2(320,320); circle.properties.shape="ellipse"; circle.properties.color=Color("76e4c5")
			var text:=studio.add_layer("text"); text.position=Vector2(180,215); text.dimensions=Vector2(630,220); text.properties.text="Make something\nworth looking at."; text.properties.text_settings.values.color=Color("edf7f7"); text.properties.text_settings.values.font_size=62.0; text.properties.text_settings.values.bold=true
			var caption:=studio.add_layer("text"); caption.position=Vector2(184,440); caption.dimensions=Vector2(540,90); caption.properties.text="IMAGE STUDIO  /  YOUR IDEAS, STILL EDITABLE"; caption.properties.text_settings.values.color=Color("8cbdbb"); caption.properties.text_settings.values.font_size=18.0
			var paint_target:=studio.add_layer("basic"); paint_target.label="Paint layer"
			studio.canvas.selected.assign([paint_target.id]); studio._selection_changed(); studio._set_tool("brush"); studio._preview(); studio.canvas.fit()
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://image_studio_ui.png")
			print("UI screenshot: "+ProjectSettings.globalize_path("user://image_studio_ui.png"))
			studio.open_source(bitmap); studio._set_tool("move")
			for frame in 4: await process_frame
			check(studio.inspector.get_global_rect().end.x<=root.size.x,"Image inspector remains inside the window with the full transform toolbar")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://image_studio_transform_ui.png")
	for angle in [0.0,PI*.25,PI*.5]:
		for handle in 8:
			studio.open_source(bitmap)
			var locked_layer:=studio.document.layers[0]; locked_layer.dimensions=Vector2(160,80); locked_layer.position=Vector2(140,160); locked_layer.rotation=angle; locked_layer.properties.keep_aspect=true
			studio.canvas.selected.assign([locked_layer.id]); studio.canvas.snapping=false
			var bounds:=studio.canvas.selection_bounds()
			var grips: Array[Vector2]=studio.canvas._projected_handles(Rect2(studio.canvas.origin()+bounds.position*studio.canvas.zoom,bounds.size*studio.canvas.zoom))
			var anchor: Vector2=studio.canvas.to_document(grips[(handle+4)%8]); var dragged: Vector2=studio.canvas.to_document(grips[handle])
			studio.canvas._bounds=bounds; studio.canvas._start=dragged; studio.canvas._begin_transform("resize"+str(handle))
			for factor in [.5,1.5,.75,1.0,.6]:
				studio.canvas._transform(anchor+(dragged-anchor)*factor,false)
				var actual:=studio.canvas.selection_bounds()
				check(actual.position.is_equal_approx(anchor+(bounds.position-anchor)*factor) and actual.size.is_equal_approx(bounds.size*factor),"Aspect-locked resizing keeps its opposite anchor through shrink/grow/reverse on handle %d" % handle)
			studio.canvas._finish(dragged)
			studio.undo()
			check(studio.document.layers[0].dimensions.is_equal_approx(Vector2(160,80)),"Aspect-locked resize undo restores dimensions")
			studio.redo()
			check(studio.document.layers[0].dimensions.is_equal_approx(Vector2(96,48)),"Aspect-locked resize redo restores the resized dimensions")
	studio.open_source(null); var performance_layer:=studio.document.layers[0]; studio.canvas.selected.assign([performance_layer.id])
	performance_layer.dimensions=Vector2(160,80); performance_layer.position=Vector2(100,120); performance_layer.rotation=PI*.5; performance_layer.properties.keep_aspect=false
	studio.canvas.snapping=false; studio.canvas._bounds=studio.canvas.selection_bounds()
	var old_bounds:=studio.canvas._bounds
	studio.canvas._start=studio.document.world_transform(performance_layer)*Vector2(performance_layer.dimensions.x,performance_layer.dimensions.y*.5)
	studio.canvas._begin_transform("resize3")
	studio.canvas._transform(studio.canvas._start+Vector2(0,40),false)
	var resized_bounds:=studio.canvas.selection_bounds()
	check(resized_bounds.position.is_equal_approx(old_bounds.position) and is_equal_approx(resized_bounds.size.y,old_bounds.size.y+40) and is_equal_approx(resized_bounds.size.x,old_bounds.size.x),"Resizing a rotated layer follows its own axes and preserves the opposite edge")
	studio.canvas._finish(studio.canvas._start+Vector2(0,40))
	var old_basis:=performance_layer.local_transform()
	studio._flip_layer(true)
	check(performance_layer.local_transform().x.is_equal_approx(old_basis.x*Vector2(-1,1)) and performance_layer.local_transform().y.is_equal_approx(old_basis.y*Vector2(-1,1)),"Horizontal flip uses canvas axes after rotation")
	studio.fill_selected_to_parent()
	check(performance_layer.rotation==0 and performance_layer.local_transform().x.is_equal_approx(Vector2.RIGHT) and performance_layer.dimensions==Vector2(studio.document.canvas_size),"Fill resets orientation to the canvas axes")
	studio.canvas.tool="brush"; studio.canvas._active_mode="freehand"; studio.canvas.brush_size=40; studio.canvas.brush_opacity=.25; studio.canvas.hardness=1; studio.canvas.color=Color.RED
	studio.canvas._begin_paint(Vector2(60,60))
	for repeat in 12: studio.canvas._paint_line(Vector2(60,60),Vector2(60,60))
	studio.canvas._finish(Vector2(60,60))
	check(absf(performance_layer.texture.get_image().get_pixel(60,60).a-.25)<.02,"Overlapping stamps never exceed stroke opacity")
	studio.canvas._begin_paint(Vector2(60,60)); studio.canvas._finish(Vector2(60,60))
	check(absf(performance_layer.texture.get_image().get_pixel(60,60).a-.4375)<.02,"Separate brush strokes can build opacity")
	check(Rect2(Vector2.ZERO,studio.canvas.size).has_point(studio.canvas._shape_screen_handle(Vector2(100000,100000))),"Offscreen shape handles stay reachable")
	studio.canvas._active_mode="circle"; studio.canvas._start=Vector2.ZERO; studio.canvas._shape_end=Vector2(100,100); studio.canvas._circle_profiles=Vector4(2,2,2,2)
	var round_path:=studio.canvas._shape_path()
	studio.canvas._shape_handle=4; studio.canvas._move_shape_handle(Vector2(96,96),false)
	check(studio.canvas._circle_profiles.x>2 and studio.canvas._shape_path()!=round_path and studio.canvas._shape_end==Vector2(100,100),"Circle profile handles change curvature without resizing")
	studio.canvas._active_mode="line"; check(studio.canvas._shape_handles().is_empty(),"Line guides expose no unreachable handles")
	studio.canvas._active_mode="freehand"
	studio.canvas.brush_opacity=1
	studio.open_source(null); performance_layer=studio.document.layers[0]; studio.canvas.selected.assign([performance_layer.id])
	studio.canvas.tool="fill"; studio.canvas.color=Color("367dd8"); studio.canvas.fill_threshold=.08
	var fill_started:=Time.get_ticks_msec(); studio.canvas._begin_paint(Vector2(20,20)); var fill_elapsed:=Time.get_ticks_msec()-fill_started
	check(fill_elapsed<2500 and performance_layer.texture.get_image().get_pixel(1000,500).b>.5,"Full-canvas fill uses the optimized scanline path")
	studio.canvas.tool="brush"; studio.canvas.brush_size=500; studio.canvas.color=Color("ef8b55")
	var brush_started:=Time.get_ticks_msec(); studio.canvas._begin_paint(Vector2(640,360)); studio.canvas._finish(Vector2(640,360)); var brush_elapsed:=Time.get_ticks_msec()-brush_started
	check(brush_elapsed<1500,"Large brushes use native cached stamps")
	for mode in ["line","curve","circle"]:
		studio.canvas._active_mode=mode
		var stroke_started:=Time.get_ticks_msec()
		studio.canvas._begin_paint(Vector2(200,200))
		studio.canvas._shape_end=Vector2(1000,550); studio.canvas._shape_control=Vector2(550,50)
		check(studio.canvas._drag=="shape_stroke","Shaped strokes use a non-destructive guide")
		studio.canvas.confirm_stroke()
		var stroke_elapsed:=Time.get_ticks_msec()-stroke_started
		print("%s 500px stroke: %d ms" % [mode,stroke_elapsed])
		check(stroke_elapsed<1500 and studio.canvas._drag.is_empty(),"Shaped strokes commit promptly as one edit")
	print("500px brush: %d ms; fill: %d ms" % [brush_elapsed,fill_elapsed])
	check_clipped_resize_handles(studio)
	check_projected_resize(studio)
	check_selection_motion(studio)
	await check_productivity_systems(studio)
	if DisplayServer.get_name()!="headless":
		await check_workflow_panels(studio)
		await check_yaw_live_resize(studio)
		await check_toolbar_input(studio)
		await check_layer_tools(studio)
		await check_revision_interactions(studio)
	studio.free()
	await process_frame
	print("Image Studio checks: %d failures" % failures)
	quit(failures)


func check_productivity_systems(studio: KiwiImageWorkspace) -> void:
	var source:=Image.create(16,16,false,Image.FORMAT_RGBA8); source.fill(Color.TRANSPARENT); source.fill_rect(Rect2i(5,5,6,6),Color.RED)
	studio.open_source(ImageTexture.create_from_image(source))
	if DisplayServer.get_name()!="headless": await studio._smart_select("opaque")
	else:
		var initial_mask:=Image.create(16,16,false,Image.FORMAT_RGBA8); initial_mask.fill(Color.TRANSPARENT); initial_mask.fill_rect(Rect2i(5,5,6,6),Color.WHITE); studio._commit_selection_bitmap(initial_mask)
	check(studio.canvas.selected_pixel(Vector2(7,7)) and not studio.canvas.selected_pixel(Vector2(1,1)),"Smart subject selection uses visible pixels")
	studio._modify_selection("grow",1)
	check(studio.canvas.selected_pixel(Vector2(4,7)),"Selection refinement grows the editable mask")
	studio._source_to_mask(false)
	check(studio._main_layer().mask!=null,"Layer opacity creates a reusable mask")
	for kind in ["sharpen","pixelate","grain","chromatic","halftone","posterize","vignette","gradient_map","color_replace","twirl"]: studio.add_effect(kind)
	check(studio._main_layer().effects.size()==10,"Expanded non-destructive effect stack is available")
	check(studio._commands.any(func(command: Dictionary): return command.name=="Select subject") and studio._commands.any(func(command: Dictionary): return command.name=="Vector union"),"Command palette indexes productivity actions")
	studio._variants.test=studio.document.snapshot(); studio._main_layer().label="Changed"; studio._restore_variant("test")
	check(studio._main_layer().label!="Changed","Named variants restore the complete document")
	var before:=studio.document.layers.size(); studio._macros.quick=["Add text layer"]; studio._run_macro("quick")
	check(studio.document.layers.size()==before+1,"Command macros replay recorded actions")
	studio.open_source(null); studio.document.layers.clear()
	var left:=studio.add_layer("shape"); left.position=Vector2(10,10); left.dimensions=Vector2(40,40)
	var right:=studio.add_layer("shape"); right.position=Vector2(30,10); right.dimensions=Vector2(40,40)
	studio.canvas.selected.assign([left.id,right.id]); studio._boolean_shapes("union")
	check(studio.document.layers.size()==1 and studio.document.layers[0].kind=="path","Vector boolean union creates one editable path")


func check_workflow_panels(studio: KiwiImageWorkspace) -> void:
	for action in [studio._transform_panel,studio._selection_panel,studio._effects_panel,studio._asset_shelf,studio._variants_panel,studio._automation_panel,studio._export_presets_panel]:
		action.call(); await process_frame
		var found:=false
		for child in studio.get_children():
			if child is PopupPanel and is_instance_valid(child): found=true; child.hide()
		check(found,"Workflow panel opens without runtime errors")
		await process_frame


func check_layer_tools(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null); await process_frame
	studio.canvas.zoom=2.0; studio.canvas.pan=Vector2(160,-90)
	var expected_center:=studio.canvas.to_document(studio.canvas.size*.5)
	for kind in ["text","shape"]:
		var added:=studio.add_layer(kind)
		check((added.position+added.dimensions*.5).is_equal_approx(expected_center) and added.dimensions.x*studio.canvas.zoom<studio.canvas.size.x,"New text/shape layers fit the current panned and zoomed view")
		check(not added.properties.keep_aspect,"Text and shape aspect ratios default to unlocked")
	studio.document.canvas_size=Vector2i(128,128)
	var shape:=studio._main_layer(); shape.position=Vector2(16,16); shape.dimensions=Vector2(96,96); shape.properties.shape="triangle"; shape.properties.color=Color.WHITE
	studio.document.layers.assign([shape]); studio.renderer.sync(studio.document)
	var triangle:=await studio.renderer.flattened()
	check(triangle.get_pixel(20,20).a<.1 and triangle.get_pixel(64,80).a>.9,"Triangle shapes render filled interiors")
	studio._draw_custom_shape(shape)
	var down:=InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true
	down.position=studio.canvas.origin()+Vector2(20,20)*studio.canvas.zoom
	studio.canvas._input_canvas(down)
	check(studio.canvas._points.size()==1,"First polygon vertex is stored and previewed immediately")
	var motion:=InputEventMouseMotion.new(); motion.position=studio.canvas.origin()+Vector2(30,30)*studio.canvas.zoom
	studio.canvas._input_canvas(motion)
	check(studio.canvas._points[0].is_equal_approx(Vector2(30,30)),"Held polygon vertex follows the mouse")
	var cancel:=InputEventMouseButton.new(); cancel.button_index=MOUSE_BUTTON_RIGHT; cancel.pressed=true; cancel.position=motion.position
	studio.canvas._input_canvas(cancel)
	check(studio.canvas._points.is_empty(),"Right click cancels the uncommitted vertex")
	studio.canvas._points=PackedVector2Array([Vector2(20,20),Vector2(100,20),Vector2(60,100)])
	studio.canvas.finish_path()
	check(shape.kind=="shape" and shape.properties.shape=="custom" and shape.properties.points.size()==3,"Custom points create a closed polygon on the shape layer")
	shape.properties.filled=false; shape.properties.stroke=4.0; studio.renderer.sync(studio.document)
	var outlined:=await studio.renderer.flattened()
	check(outlined.get_pixel(60,50).a<.1 and outlined.get_pixel(60,20).a>.5,"Custom shapes support outline-only rendering")
	studio.open_source(null); studio.document.canvas_size=Vector2i(256,256); studio.document.layers.clear()
	var text:=studio.add_layer("text"); text.position=Vector2(10,10); text.dimensions=Vector2(130,10)
	text.properties.text="First\nSecond\nThird\nFourth"; text.properties.text_settings.values.font_size=24.0; text.properties.text_settings.values.color=Color.RED
	studio.renderer.sync(studio.document)
	var text_image:=await studio.renderer.flattened()
	check(text_image.get_used_rect().end.y>80,"Text overflow is rendered below its layout box")
	check(studio.canvas.hit(Vector2(30,90))==text,"Overflowing text remains clickable outside its layout box")
	text.properties.text_settings.set_value(&"color",Color.GREEN); studio.renderer.sync(studio.document)
	var changed:=await studio.renderer.flattened(); var green:=0.0
	for y in changed.get_height():
		for x in changed.get_width(): green+=changed.get_pixel(x,y).g*changed.get_pixel(x,y).a
	check(green>100,"Editing nested text settings redraws the text without reselection")
	text.dimensions=Vector2(70,30); studio.renderer.sync_transforms(studio.document)
	check(studio.renderer.views[text.id].output.scale.is_equal_approx(Vector2.ONE),"Live text resize rebuilds layout rather than stretching old pixels")
	check(studio.renderer.views[text.id].direct_text.visible,"Plain text avoids reallocating render surfaces during resize")
	studio.canvas.selected.assign([text.id]); studio._edit_canvas_text()
	var inline_editor: TextEdit=null
	for child in studio.canvas.get_children():
		if child is TextEdit: inline_editor=child
	check(inline_editor!=null and inline_editor.has_focus(),"Text editing opens a focused on-canvas insertion editor")
	if inline_editor!=null:
		inline_editor.text="Edited in canvas"; inline_editor.text_changed.emit()
		check(text.properties.text=="Edited in canvas","Inline editing updates layer text immediately")
		inline_editor.release_focus(); await process_frame
	var source:=Image.create(32,32,false,Image.FORMAT_RGBA8); source.fill(Color.RED); source.fill_rect(Rect2i(16,0,16,32),Color.GREEN)
	studio.open_source(source); studio.canvas.tool="pixel_select"; await studio._prepare_pixel_selection()
	studio.canvas.pixel_mode="fill"; studio.canvas.fill_threshold=0
	studio.canvas._begin_pixel_selection(Vector2(4,4))
	check(studio.canvas.selection.get_pixel(4,4).a>.9 and studio.canvas.selection.get_pixel(20,4).a<.1,"Selection fill follows connected colors at its threshold")
	if OS.get_cmdline_user_args().has("--visual"):
		studio._refresh_context(); studio.canvas.fit()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://image_studio_pixel_selection.png")
	studio.canvas.tool="move"; studio.undo(); check(studio.document.pixel_selection==null,"Pixel selection is undoable")
	studio.redo(); check(studio.document.pixel_selection!=null,"Pixel selection is redoable")
	studio.canvas.tool="pixel_select"; await studio._prepare_pixel_selection()
	studio.canvas.pixel_mode="erase"; studio.canvas.brush_size=4
	studio.canvas._begin_pixel_selection(Vector2(4,4)); studio.canvas._finish(Vector2(4,4))
	check(studio.canvas.selection.get_pixel(4,4).a<.1 and studio.canvas.selection.get_pixel(12,4).a>.9,"Selection eraser subtracts from the mask")
	studio.canvas.pixel_mode="brush"; studio.canvas._begin_pixel_selection(Vector2(4,4)); studio.canvas._finish(Vector2(4,4))
	check(studio.canvas.selection.get_pixel(4,4).a>.9,"Selection brush adds to the mask")
	studio._apply_pixel_selection("extract")
	check(studio.document.layers.size()==2,"Extract creates a separate selected-pixels layer")
	var remaining:=studio.document.layers[0]; var cut:=studio.document.layers[1]
	check(remaining.position.x==16 and cut.position.x==0 and cut.texture.get_image().get_pixel(4,4).r>.9,"Extract removes only selected pixels from the source")
	studio.undo(); check(studio.document.layers.size()==1 and studio.document.pixel_selection!=null,"Extract undoes both pixel deletion and layer creation")
	studio.canvas.clear_selection()
	studio.canvas.pixel_source=source.duplicate(); studio.canvas.pixel_source.set_pixel(25,4,Color.RED)
	studio.canvas.pixel_match_all=true; studio.canvas.pixel_mode="fill"
	studio.canvas._begin_pixel_selection(Vector2(4,4))
	check(studio.canvas.selection.get_pixel(25,4).a>.9,"All matching colors includes disconnected regions")
	studio.canvas.pixel_match_all=false
	studio._set_tool("pixel_select")
	for frame in 3: await process_frame
	var canvas_top: float=studio.canvas.global_position.y
	studio._set_tool("brush")
	for frame in 3: await process_frame
	check(canvas_top<studio.canvas.global_position.y,"Hiding the preset panel gives its vertical space back to the canvas")
	check(is_equal_approx(studio.preset_panel.size.x,studio._main_split.size.x),"Preset panel extends across the right-hand sidebar")
	var basic:=studio.add_layer("basic")
	studio.canvas.selected.assign([basic.id]); studio._refresh_layers()
	var image_item:=studio.layer_tree.get_root().get_first_child()
	while image_item!=null and studio.document.layer_for_id(str(image_item.get_metadata(0))).kind!="image": image_item=image_item.get_next()
	studio.layer_tree.deselect_all()
	studio._tree_selected(image_item,0,true)
	image_item.select(0)
	await process_frame
	check(studio.canvas.selected.size()==1 and studio._main_layer().kind=="image","Deferred layer selection switches from Basic to Image without retaining the old selection")


func check_revision_interactions(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null)
	await process_frame
	var text:=studio.add_layer("text")
	text.properties.text="Tiny text, sharp at 32×"; text.properties.text_settings.values.font_size=2.0
	text.dimensions=Vector2(30,8); text.position=Vector2(630,350)
	studio._set_tool("move"); studio.renderer.sync(studio.document)
	studio.canvas.zoom=32; studio.canvas.pan=(Vector2(studio.document.canvas_size)*.5-(text.position+text.dimensions*.5))*32
	for frame in 4: await process_frame
	var view: Dictionary=studio.renderer.views[text.id]
	check(view.direct_text.text_detail>=32,"Tiny text is rasterized at display zoom instead of enlarging two-pixel glyphs")
	var target_size: Vector2i=view.base.size
	var viewport_size: Vector2i=studio.renderer.viewport.size
	for zoom in [16.0,4.0,1.0,.5,.1,32.0]:
		studio.canvas.zoom=zoom
		await process_frame
		check(view.base.size==target_size and studio.renderer.viewport.size==viewport_size,"Zoom does not reallocate layer or composition render targets")
	studio.canvas.pan=(Vector2(studio.document.canvas_size)*.5-(text.position+text.dimensions*.5))*32
	for frame in 3: await process_frame
	if OS.get_cmdline_user_args().has("--visual"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://image_studio_tiny_text.png")
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.double_click=true
	click.position=studio.canvas.origin()+(text.position+Vector2(2,1))*studio.canvas.zoom
	studio.canvas._input_canvas(click)
	click.pressed=false; click.double_click=false; studio.canvas._input_canvas(click)
	for frame in 8: await process_frame
	var editor: TextEdit=null
	for child in studio.canvas.get_children():
		if child is TextEdit: editor=child
	check(editor!=null and editor.has_focus(),"Mouse release after a double-click does not close inline text editing")
	if editor!=null:
		text.properties.alignment=HORIZONTAL_ALIGNMENT_CENTER
		editor.sync_layout()
		check(editor.paragraph.alignment==HORIZONTAL_ALIGNMENT_CENTER,"Inline text preserves centered alignment")
		var aligned_start: float=(editor.paragraph.width-editor.paragraph.get_line_width(0))*.5
		check(editor.hit_text(Vector2(aligned_start,editor.font_size*.5))==0,"Centered text caret hit-testing uses the rendered alignment")
		check(editor.caret_rect_for_line(0,3).position.x>editor.caret_rect_for_line(0,0).position.x,"Caret advances horizontally to its character instead of staying at the row start")
		editor._place_caret(3)
		var old_position: Vector2=editor.position
		studio.canvas.pan+=Vector2(47,23); studio.canvas.set_zoom(16)
		editor.sync_layout()
		check(not editor.position.is_equal_approx(old_position) and editor.detail==16,"Inline text follows canvas pan and zoom")
		check(editor.get_theme_stylebox("normal") is StyleBoxEmpty,"Inline text does not draw a second bounding box")
		if OS.get_cmdline_user_args().has("--visual"):
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://image_studio_inline_text.png")
		editor.release_focus()
	await process_frame
	var shape:=studio.add_layer("shape"); studio._draw_custom_shape(shape)
	var points:=PackedVector2Array([Vector2(100,100),Vector2(180,100),Vector2(180,180),Vector2(100,180)])
	studio.canvas._points=points.duplicate(); studio.canvas.polygon_committed.emit(points.duplicate())
	check(shape.properties.points.size()==4,"Polygon vertices are persisted without Enter")
	studio._set_tool("move")
	check(shape.properties.points.size()==4,"Leaving polygon editing preserves points")
	var rounded:=KiwiImageLayer.rounded_polygon(points,12)
	check(rounded.size()>4 and not rounded.has(points[0]),"Custom polygon corners create rounded segments")
	studio._draw_custom_shape(shape); var shape_id:=shape.id; studio.delete_selected()
	for frame in 2: await process_frame
	check(studio.canvas.tool=="move","Deleting the polygon exits its editor")
	studio.undo(); check(studio.document.layer_for_id(shape_id)!=null,"Polygon deletion is undoable")
	text=studio.document.layer_for_id(text.id)
	studio._action(func(): text.isolated=true)
	check(studio.document.isolation_allows(text) and not studio.document.isolation_allows(studio.document.layer_for_id(shape_id)),"Isolation hides other layers without altering visibility flags")
	studio.undo(); check(not studio.document.layer_for_id(text.id).isolated,"Isolation is undoable")
	var pixels:=Image.create(16,16,false,Image.FORMAT_RGBA8); pixels.fill(Color.TRANSPARENT); pixels.fill_rect(Rect2i(0,0,8,16),Color(1,0,0,.1))
	studio.open_source(pixels); studio._set_tool("pixel_select")
	await studio._select_pixel_region(false)
	check(studio.canvas.selected_pixel(Vector2(2,2)) and not studio.canvas.selected_pixel(Vector2(12,2)),"Non-transparent selection includes partially transparent pixels")
	await studio._select_pixel_region(true)
	check(not studio.canvas.selected_pixel(Vector2(2,2)) and studio.canvas.selected_pixel(Vector2(12,2)),"Invert selects the complementary pixels")
	studio.canvas.paint_selection_only=true
	check(not studio.canvas._paint_pixel_allowed(Vector2(2,2)),"Selection-only painting excludes unselected pixels")
	studio.canvas.paint_selection_only=false
	check(studio.canvas._paint_pixel_allowed(Vector2(2,2)),"Unrestricted painting ignores stored selections")
	studio.canvas.snapping=true; studio.canvas.zoom=1
	studio.canvas._points=PackedVector2Array([Vector2(5,7),Vector2(12,14)])
	studio.canvas._polygon_index=1
	check(studio.canvas._snap_polygon_point(Vector2(6,6)).is_equal_approx(Vector2(5,7)),"Polygon points snap to other vertices")
	check(studio.canvas._snap_polygon_point(Vector2(6,6),true).is_equal_approx(Vector2(6,6)),"Ctrl temporarily disables polygon snapping")
	var blank:=Image.create(64,64,false,Image.FORMAT_RGBA8); blank.fill(Color.TRANSPARENT)
	var results: Array[Image]=[]
	for masked in [false,true]:
		studio.open_source(blank); studio.canvas.tool="brush"; studio.canvas._active_mode="freehand"
		studio.canvas.brush_size=18; studio.canvas.brush_opacity=.25; studio.canvas.hardness=.6; studio.canvas.color=Color.RED
		studio.canvas.paint_selection_only=masked
		studio.canvas.selection=Image.create(64,64,false,Image.FORMAT_RGBA8); studio.canvas.selection.fill(Color.WHITE)
		studio.canvas._begin_paint(Vector2(20,20))
		for repeat in 12: studio.canvas._paint_line(Vector2(20,20),Vector2(20,20))
		studio.canvas._finish(Vector2(20,20))
		results.append(studio._main_layer().texture.get_image())
	check(results[0].get_data()==results[1].get_data(),"Selection-only strokes use exactly the same opacity accumulation as unrestricted strokes")


func check_selection_motion(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null)
	var layer:=studio._main_layer()
	var mask:=Image.create(1280,720,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(20,30,10,10),Color.WHITE)
	studio.document.pixel_selection=ImageTexture.create_from_image(mask); studio.document.pixel_selection_owner=layer.id; studio.canvas.sync_pixel_selection()
	studio.canvas.snapping=false; studio.canvas._bounds=studio.canvas.selection_bounds(); studio.canvas._start=Vector2(100,100)
	studio.canvas._begin_transform("move"); studio.canvas._transform(Vector2(140,130),false)
	check(studio.canvas.selected_pixel(Vector2(65,65)) and not studio.canvas.selected_pixel(Vector2(25,35)),"Pixel selection follows layer translation")
	studio.canvas._finish(Vector2(140,130))
	studio.undo()
	check(studio.canvas.selected_pixel(Vector2(25,35)) and not studio.canvas.selected_pixel(Vector2(65,65)),"Undo restores both layer and pixel selection")
	studio.redo()
	check(studio.canvas.selected_pixel(Vector2(65,65)),"Redo restores the moved pixel selection")
	for angle in [0.0,.7,PI*.5]:
		studio.open_source(null)
		layer=studio._main_layer(); layer.dimensions=Vector2(160,100); layer.position=Vector2(220,160)
		var selected_point:=Vector2(250,190)
		var source_mask:=Image.create(1280,720,false,Image.FORMAT_RGBA8); source_mask.fill_rect(Rect2i(245,185,10,10),Color.WHITE)
		studio.document.pixel_selection=ImageTexture.create_from_image(source_mask); studio.document.pixel_selection_owner=layer.id; studio.canvas.sync_pixel_selection()
		var original_world:=studio.document.world_transform(layer)
		studio._begin(); studio.document.resize_layer(layer,Vector2(260,170)); layer.rotation=angle; studio._preview()
		var mapping:=studio.document.world_transform(layer).scaled_local(Vector2(260,170)/Vector2(160,100))*original_world.affine_inverse()
		var target:=mapping*selected_point
		check(studio.canvas.selected_pixel(target),"Selection follows resizing and rotation live")
		studio._commit(); check(studio.canvas.selected_pixel(target),"Transformed selection survives gesture commit")
		studio.undo(); check(studio.canvas.selected_pixel(selected_point),"Undo restores pre-transform selection")
		studio.redo(); check(studio.canvas.selected_pixel(target),"Redo restores resized and rotated selection")
	# Perspective yaw is not affine and the selected area may temporarily live
	# entirely outside the canvas. It must still return intact when the layer does.
	studio.open_source(null)
	layer=studio._main_layer(); layer.dimensions=Vector2(180,120); layer.position=Vector2(180,140)
	var yaw_point:=Vector2(220,180)
	var yaw_mask:=Image.create(1280,720,false,Image.FORMAT_RGBA8); yaw_mask.fill_rect(Rect2i(215,175,12,12),Color.WHITE)
	studio.document.pixel_selection=ImageTexture.create_from_image(yaw_mask); studio.document.pixel_selection_owner=layer.id; studio.canvas.sync_pixel_selection()
	studio._begin(); layer.properties.yaw_left_right=68.0; layer.properties.yaw_up_down=35.0; layer.position=Vector2(-900,-500); studio._preview()
	var old_layer:=studio._before.pixel_selection_reference
	var old_world:=studio._before.pixel_selection_reference_world
	var local:=old_layer.unproject_point(old_world.affine_inverse()*yaw_point)
	var offscreen:=studio.document.world_transform(layer)*layer.project_point(local/old_layer.dimensions*layer.dimensions)
	check(studio.canvas.selected_pixel(offscreen),"Pixel selection follows nonlinear yaw even outside the canvas")
	studio._commit()
	studio._begin(); layer.position=Vector2(180,140); layer.properties.yaw_left_right=0.0; layer.properties.yaw_up_down=0.0; studio._preview()
	check(studio.canvas.selected_pixel(yaw_point),"Off-canvas yaw does not delete selected pixels when the layer returns")
	studio._commit()
	studio.open_source(null)
	layer=studio._main_layer(); layer.properties.value_basics={"brightness":.1,"saturation":.7}
	studio.canvas.tool="brush"; studio.canvas.paint_selection_only=false; studio.canvas.brush_size=800; studio.canvas.hardness=.7; studio.canvas.brush_opacity=1
	var started:=Time.get_ticks_msec(); studio.canvas._begin_paint(Vector2(500,300)); studio.canvas._paint_line(Vector2(500,300),Vector2(550,300)); var elapsed:=Time.get_ticks_msec()-started
	print("800px adjusted brush: %d ms" % elapsed)
	check(elapsed<1200,"Adjusted large brush avoids per-pixel inverse color solving")
	studio.canvas._finish(Vector2(550,300))


func check_yaw_live_resize(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null); studio.document.layers.clear()
	var layer:=studio.add_layer("text"); layer.properties.text="Yaw resize"; layer.properties.yaw_up_down=25; layer.properties.yaw_left_right=40
	layer.position=Vector2(50,50); layer.dimensions=Vector2(350,180)
	studio.renderer.sync(studio.document)
	for frame in 6: await RenderingServer.frame_post_draw
	var view: Dictionary=studio.renderer.views[layer.id]
	var allocated: Vector2i=view.base.size
	var normalized:=layer.project_point(Vector2(.2,.8)*layer.dimensions)/layer.dimensions
	for extent in [Vector2(420,150),Vector2(280,240),Vector2(510,200),Vector2(350,180)]:
		studio.document.resize_layer(layer,extent); studio.renderer.sync_transforms(studio.document)
		check((layer.project_point(Vector2(.2,.8)*extent)/extent).distance_to(normalized)<.00001,"Changing aspect ratio preserves the yaw profile")
		check(view.base.size==allocated,"Yawed text keeps stable GPU surfaces while resizing")
		for frame in 5: await RenderingServer.frame_post_draw
		var texture: Image=view.output.texture.get_image()
		check(texture.get_used_rect().has_area(),"Yawed text stays rendered during aspect-ratio resizing")


func check_toolbar_input(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null); studio._set_tool("values")
	for frame in 3: await process_frame
	check(studio._context_panel.get_parent()==studio,"Spanning toolbar is outside sidebar hit-testing ancestors")
	var target: HSlider=null
	for column in studio.context.get_children():
		for child in column.get_children():
			if child is HSlider and child.get_global_rect().get_center().x>studio._side_split.global_position.x: target=child
	check(target!=null,"A value slider extends above the right-hand inspector")
	if target!=null:
		var at:=target.get_global_rect().position+Vector2(target.size.x*.8,target.size.y*.5)
		var motion:=InputEventMouseMotion.new(); motion.position=at; root.push_input(motion,true)
		await process_frame
		var hovered:=root.gui_get_hovered_control()
		check(hovered==target or target.is_ancestor_of(hovered),"Right-side toolbar receives mouse input above the inspector")
	studio._set_tool("move")


func check_projected_resize(studio: KiwiImageWorkspace) -> void:
	for angle in [.3,.8,1.57]:
		for yaw in [Vector2.ZERO,Vector2(25,40),Vector2(-50,0),Vector2(80,80),Vector2(88,-88),Vector2(-85,85)]:
			studio.open_source(null)
			var layer:=studio._main_layer(); layer.dimensions=Vector2(160,80); layer.position=Vector2(200,180); layer.rotation=angle
			layer.properties.yaw_up_down=yaw.x; layer.properties.yaw_left_right=yaw.y; layer.properties.keep_aspect=false
			var local:=Vector2(40,25)
			check(layer.unproject_point(layer.project_point(local)).distance_to(local)<.1,"Yaw projection and picking match within a tenth of a source pixel even near edge-on")
			var basis:=layer.local_transform()
			var world:=studio.document.world_transform(layer)
			var anchor:=world*layer.projected_bounds().position
			var start:=world*layer.projected_bounds().end
			studio.canvas.snapping=false; studio.canvas._bounds=studio.canvas.selection_bounds(); studio.canvas._start=start; studio.canvas._begin_transform("resize4")
			var desired:=start+world.basis_xform(Vector2(25,18))
			studio.canvas._transform(desired,false)
			var updated:=studio.document.world_transform(layer)
			check((updated*layer.projected_bounds().position).distance_to(anchor)<.01,"Rotated/yawed resize keeps the opposite projected envelope corner fixed")
			check((updated*layer.projected_bounds().end).distance_to(desired)<.1,"Steep-yaw resize tracks the cursor without singular corner diagonals")
			check(layer.local_transform().x.is_equal_approx(basis.x) and layer.local_transform().y.is_equal_approx(basis.y),"Resizing never inserts shear into the layer basis")
			studio.canvas._finish(desired)


func check_clipped_resize_handles(studio: KiwiImageWorkspace) -> void:
	studio.open_source(null)
	studio.color_picker.color=Color.RED
	var text:=studio.add_layer("text")
	check(text.properties.color==Color.WHITE and text.properties.text_settings.values.color==Color.WHITE,"New text is white regardless of the current brush color")
	for index in [0,2,4,6]:
		studio.open_source(null)
		var layer:=studio._main_layer()
		layer.dimensions=Vector2(4000,3000)
		layer.position=(Vector2(studio.document.canvas_size)-layer.dimensions)*.5
		layer.properties.keep_aspect=true
		studio.canvas.zoom=1; studio.canvas.pan=Vector2.ZERO; studio.canvas.snapping=false
		var bounds:=studio.canvas.selection_bounds()
		studio.canvas._bounds=bounds
		var screen:=Rect2(studio.canvas.origin()+bounds.position,bounds.size)
		var grip: Vector2=studio.canvas._handles(screen)[index]
		studio.canvas._start=studio.canvas.to_document(grip)
		studio.canvas._begin_transform("resize"+str(index))
		check(studio.canvas._resize_proxy_active,"Oversized corner starts a proxy-handle drag")
		studio.canvas._transform(studio.canvas._start,false)
		check(studio.canvas.selection_bounds().is_equal_approx(bounds),"Clamped corner does not resize or jump before the mouse moves")
		var direction:=Vector2(1 if index in [0,6] else -1,1 if index in [0,2] else -1)
		for amount in [Vector2(30,20),Vector2(12,45),Vector2(45,12),Vector2.ZERO,Vector2(25,35)]:
			var mouse: Vector2=grip+amount*direction
			studio.canvas._transform(studio.canvas.to_document(mouse),false)
			var updated:=studio.canvas.selection_bounds()
			var shown: Vector2=studio.canvas._handles(Rect2(studio.canvas.origin()+updated.position,updated.size))[index]
			check(shown.is_equal_approx(mouse),"Clamped corner stays under the cursor during aspect-locked dragging")
			check(is_equal_approx(updated.size.x/updated.size.y,bounds.size.x/bounds.size.y),"Clamped corner preserves aspect ratio while changing direction")
			var opposite: int=(index+4)%8
			check(studio.canvas._raw_handles(updated)[opposite].is_equal_approx(studio.canvas._raw_handles(bounds)[opposite]),"Aspect-locked proxy resizing preserves the opposite corner")
		studio.canvas._finish(studio.canvas._start+Vector2(25,35)*direction)
		studio.undo()
		check(studio.canvas.selection_bounds().is_equal_approx(bounds),"Clamped corner resize can be undone")
