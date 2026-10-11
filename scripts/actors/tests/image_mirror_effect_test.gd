extends SceneTree
var failures:=0

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var studio:=KiwiImageWorkspace.new(); root.add_child(studio)
	var document:=KiwiImageDocument.new(); document.canvas_size=Vector2i(16,8)
	var layer:=KiwiImageLayer.create("basic",document.canvas_size)
	var pixels:=Image.create(16,8,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.BLUE); pixels.fill_rect(Rect2i(0,0,8,8),Color.RED)
	layer.texture=ImageTexture.create_from_image(pixels); layer.paint_base=layer.texture
	document.layers.append(layer); studio.document=document; studio.canvas.document=document
	studio.canvas.selected.assign([layer.id]); studio.add_effect("mirror")
	check(layer.texture.get_image().get_pixel(13,4).b>.9,"Adding mirror preserves source pixels")
	for side in 4:
		layer.effects[0].mirror_side=side
		studio.renderer.sync(document)
		var result: Image=await studio.renderer.flattened()
		if side==0: check(result.get_pixel(13,4).r>.9,"Left side mirrors across the layer")
		if side==1: check(result.get_pixel(2,4).b>.9,"Right side mirrors across the layer")
	layer.effects[0].mirror_side=0
	await studio._apply_effect(layer,0)
	check(layer.effects.is_empty(),"Apply removes the baked effect")
	check(layer.texture.get_image().get_pixel(13,4).r>.9,"Apply commits mirrored pixels")
	studio.undo()
	check(studio.document.layers[0].effects.size()==1,"Undo restores the editable mirror")
	check(studio.document.layers[0].texture.get_image().get_pixel(13,4).b>.9,"Undo restores the source pixels")
	studio.redo()
	check(studio.document.layers[0].effects.is_empty(),"Redo restores the baked effect")
	layer=studio.document.layers[0]
	studio.add_effect("invert"); studio.add_effect("mirror"); studio.add_effect("grayscale")
	layer.properties.value_basics={"brightness":0.1}
	studio.renderer.sync(studio.document)
	var before: Image=await studio.renderer.flattened()
	await studio._apply_effect(layer,1)
	check(layer.effects.size()==1 and layer.effects[0].type=="grayscale","Applying a stack prefix preserves later effects")
	studio.renderer.sync(studio.document)
	var after: Image=await studio.renderer.flattened()
	check(before.get_pixel(4,4).is_equal_approx(after.get_pixel(4,4)),"Apply preserves stack order and does not bake final color adjustments twice")
	layer.effects.clear(); layer.properties.clear(); layer.texture=ImageTexture.create_from_image(pixels)
	studio.add_effect("invert")
	var selection:=Image.create(16,8,false,Image.FORMAT_RGBA8); selection.fill(Color.TRANSPARENT)
	selection.fill_rect(Rect2i(0,0,8,8),Color.WHITE)
	layer.properties.effects_selection_only=true; layer.properties.effects_selection=ImageTexture.create_from_image(selection)
	studio.renderer.sync(studio.document)
	var masked: Image=await studio.renderer.flattened()
	check(masked.get_pixel(3,4).g>.9 and masked.get_pixel(3,4).b>.9,"Effects change selected pixels")
	check(masked.get_pixel(13,4).b>.9 and masked.get_pixel(13,4).r<.1,"Effects preserve unselected pixels")
	await studio._apply_effect(layer,0)
	check(layer.texture.get_image().get_pixel(13,4).b>.9,"Applying effects preserves unselected pixels")
	layer.effects.clear(); layer.properties.clear(); layer.texture=ImageTexture.create_from_image(pixels)
	studio.canvas.selection=selection
	var controls:=VBoxContainer.new(); studio.add_child(controls)
	studio._effect_selection_control(controls,layer)
	(controls.get_child(0) as CheckBox).button_pressed=true
	check(layer.properties.effects_selection_only and layer.properties.effects_selection!=null,"Effects checkbox captures a pixel selection")
	studio.undo(); check(not studio.document.layers[0].properties.has("effects_selection_only"),"Selection-only effect settings support undo")
	studio.redo(); layer=studio.document.layers[0]
	var shader:=Shader.new(); shader.code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment(){COLOR=vec4(0.0,1.0,0.0,1.0);}"
	layer.effects.append({"id":"selection_shader","type":"shader","shader":shader,"uniforms":{},"enabled":true})
	studio.renderer.sync(studio.document)
	masked=await studio.renderer.flattened()
	check(masked.get_pixel(3,4).g>.9 and masked.get_pixel(13,4).b>.9,"Selected-only effect settings also mask canvas shader effects")
	studio.free(); await process_frame
	print("Mirror effect checks: %d failures" % failures); quit(failures)
