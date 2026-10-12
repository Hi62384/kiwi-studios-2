extends SceneTree
const Math=preload("res://Workspaces/ImageWorkspace/image_values.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var renderer:=KiwiImageRenderer.new(); root.add_child(renderer)
	var document:=KiwiImageDocument.new(); document.canvas_size=Vector2i(8,8)
	var layer:=KiwiImageLayer.create("basic",document.canvas_size)
	var input:=Color(.2,.4,.7,1); var source:=Image.create(8,8,false,Image.FORMAT_RGBA8); source.fill(input)
	input=source.get_pixel(3,3); layer.texture=ImageTexture.create_from_image(source); document.layers.append(layer)
	for kind in ["vibrance","grayscale","sepia","posterize","solarize","shadows","highlights","black_point","white_point","midtones","lift","fade","threshold","cyan_red","magenta_green","yellow_blue","shadow_warmth","highlight_warmth","colorize"]:
		var amount:=.4 if kind not in ["posterize","white_point"] else (6.0 if kind=="posterize" else 1.4)
		var op:={"type":kind,"amount":amount,"enabled":true}; layer.properties.value_operations=[op]
		renderer.sync(document); var result: Image=await renderer.flattened()
		var actual:=result.get_pixel(3,3); var wanted:=Math.evaluate(Vector3(input.r,input.g,input.b),[op])
		if Vector3(actual.r,actual.g,actual.b).distance_to(wanted)>.025:
			failures+=1; push_error("GPU adjustment and inverse-paint color math disagree for "+kind)
	layer.properties.value_operations=[]
	var red:=Curve.new(); red.add_point(Vector2(0,.8)); red.add_point(Vector2(1,.8))
	var blue:=Curve.new(); blue.add_point(Vector2(0,1)); blue.add_point(Vector2(1,0))
	var alpha:=Curve.new(); alpha.add_point(Vector2(0,.4)); alpha.add_point(Vector2(1,.4))
	layer.effects=[{"type":"curves","enabled":true,"curve":ActorValueCurve.preset("Linear"),"curves":{"red":red,"blue":blue,"alpha":alpha}}]
	renderer.sync(document); var curved: Image=await renderer.flattened(); var pixel:=curved.get_pixel(3,3)
	if absf(pixel.r-.8)>.03 or absf(pixel.g-input.g)>.03 or absf(pixel.b-blue.sample_baked(input.b))>.03 or absf(pixel.a-.4)>.03:
		failures+=1; push_error("Independent RGBA curves must affect only their matching channels")
	layer.effects=[]; renderer.sync(document)
	renderer.set_preview_camera(Vector2(100,80),Vector2(70,50),8)
	renderer.set_composition_preview_enabled(true)
	for frame in 8: await RenderingServer.frame_post_draw
	var composition:=renderer.composition_texture().get_image()
	if composition.get_size()!=document.canvas_size or composition.get_pixel(3,3).r<input.r-.03:
		failures+=1; push_error("Whole composition preview must ignore canvas camera pan and zoom")
	document.canvas_size=Vector2i(64,64); layer.dimensions=Vector2(64,64)
	var pattern:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64: pattern.set_pixel(x,y,Color(x/63.0,y/63.0,1.0 if x<24 and y<44 else .1,1))
	layer.texture=ImageTexture.create_from_image(pattern)
	for kind in ["emboss","edge_detect","motion_blur","radial_blur","kaleidoscope","ripple","scanlines"]:
		layer.effects=[{"type":kind,"amount":6.0 if kind!="scanlines" else .7,"enabled":true,"spacing":5.0,"angle":30.0}]
		renderer.sync(document); var changed: Image=await renderer.flattened()
		var difference:=0.0
		for y in range(8,56,8):
			for x in range(8,56,8): difference+=Vector4(changed.get_pixel(x,y).r,changed.get_pixel(x,y).g,changed.get_pixel(x,y).b,changed.get_pixel(x,y).a).distance_to(Vector4(pattern.get_pixel(x,y).r,pattern.get_pixel(x,y).g,pattern.get_pixel(x,y).b,pattern.get_pixel(x,y).a))
		if difference<.01: failures+=1; push_error("New effect must change the rendered pixels: "+kind)
	# A narrow impulse should become a smooth radial Gaussian, not a grid of
	var colored:=Image.create(64,64,false,Image.FORMAT_RGBA8); colored.fill(Color(.2,.4,.7,1))
	layer.texture=ImageTexture.create_from_image(colored); layer.effects=[{"type":"emboss","amount":2.0,"enabled":true,"preserve_color":true}]
	renderer.sync(document); var preserved: Image=await renderer.flattened()
	if Vector3(preserved.get_pixel(32,32).r,preserved.get_pixel(32,32).g,preserved.get_pixel(32,32).b).distance_to(Vector3(.2,.4,.7))>.02: failures+=1; push_error("Color-preserving Emboss must retain the original flat surface color")
	layer.effects[0].preserve_color=false; renderer.sync(document); var classic: Image=await renderer.flattened()
	if absf(classic.get_pixel(32,32).r-.5)>.02: failures+=1; push_error("Classic Emboss remains available when Preserve Color is disabled")
	# A narrow impulse should become a smooth radial Gaussian, not a grid of
	# isolated taps or square regions. Check both axes and masked passthrough.
	var impulse:=Image.create(64,64,false,Image.FORMAT_RGBA8); impulse.fill(Color.BLACK); impulse.fill_rect(Rect2i(27,27,10,10),Color.WHITE)
	layer.texture=ImageTexture.create_from_image(impulse); layer.effects=[{"type":"blur","amount":16.0,"enabled":true}]
	renderer.sync(document); var blurred: Image=await renderer.flattened()
	var previous:=blurred.get_pixel(32,32).r
	for i in range(1,20):
		var horizontal:=blurred.get_pixel(32+i,32).r; var vertical:=blurred.get_pixel(32,32+i).r
		if horizontal>previous+.015 or absf(horizontal-vertical)>.025: failures+=1; push_error("Gaussian blur must fall smoothly and equally along both axes")
		previous=horizontal
	var mask:=Image.create(64,64,false,Image.FORMAT_RGBA8); mask.fill_rect(Rect2i(32,0,32,64),Color.WHITE)
	layer.properties.effects_selection_only=true; layer.properties.effects_selection=ImageTexture.create_from_image(mask); layer.properties.effects_selection_frame=Transform2D.IDENTITY; layer.properties.effects_selection_dimensions=layer.dimensions
	renderer.sync(document); var masked: Image=await renderer.flattened()
	if masked.get_pixel(25,32).r>.01 or masked.get_pixel(29,32).r<.95: failures+=1; push_error("Masked two-pass blur must preserve the original unselected image, not its horizontal pass")
	renderer.free(); print("New color adjustment GPU/CPU checks: %d failures" % failures); quit(failures)
