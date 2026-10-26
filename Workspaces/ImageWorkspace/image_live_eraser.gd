extends RefCounted
## A gesture's fixed lower-layer pixels, separate from immutable history textures.
## Update only the dirty patch; repeated eraser dabs cannot accumulate opacity.
var regions: Array[Dictionary]=[]
var source_size:=Vector2i.ZERO
func begin(layer: KiwiImageLayer,size: Vector2i) -> void:
	source_size=size
	for region in layer.live_paint:
		var texture: Texture2D=region.coverage if region.is_live() else region.raster
		if texture==null: continue
		var original:=texture.get_image()
		if original==null or original.is_empty(): continue
		original.convert(Image.FORMAT_RGBA8)
		var working:=original.duplicate()
		var mutable:=ImageTexture.create_from_image(working)
		if region.is_live(): region.coverage=mutable
		else: region.raster=mutable
		regions.append({"original":original,"working":working,"texture":mutable})
func apply(area: Rect2i,coverage: Image) -> void:
	for entry in regions:
		var original: Image=entry.original; var working: Image=entry.working
		var ratio:=Vector2(original.get_size())/Vector2(source_size)
		var start:=Vector2i((Vector2(area.position)*ratio).floor())
		var end:=Vector2i((Vector2(area.end)*ratio).ceil())
		var patch:=Rect2i(start,end-start).intersection(Rect2i(Vector2i.ZERO,original.get_size()))
		for y in range(patch.position.y,patch.end.y):
			for x in range(patch.position.x,patch.end.x):
				var at:=Vector2i(Vector2(x,y)/ratio)-area.position
				at=at.clamp(Vector2i.ZERO,coverage.get_size()-Vector2i.ONE)
				var color:=original.get_pixel(x,y); color.a*=1.0-coverage.get_pixelv(at).a
				if color.a<=0: color=Color.TRANSPARENT
				working.set_pixel(x,y,color)
		(entry.texture as ImageTexture).update(working)
