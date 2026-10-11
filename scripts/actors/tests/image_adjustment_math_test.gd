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
	for kind in ["vibrance","grayscale","sepia","posterize","solarize","shadows","highlights","black_point","white_point"]:
		var amount:=.4 if kind not in ["posterize","white_point"] else (6.0 if kind=="posterize" else 1.4)
		var op:={"type":kind,"amount":amount,"enabled":true}; layer.properties.value_operations=[op]
		renderer.sync(document); var result: Image=await renderer.flattened()
		var actual:=result.get_pixel(3,3); var wanted:=Math.evaluate(Vector3(input.r,input.g,input.b),[op])
		if Vector3(actual.r,actual.g,actual.b).distance_to(wanted)>.025:
			failures+=1; push_error("GPU adjustment and inverse-paint color math disagree for "+kind)
	renderer.free(); print("New color adjustment GPU/CPU checks: %d failures" % failures); quit(failures)
