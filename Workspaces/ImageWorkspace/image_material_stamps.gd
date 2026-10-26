extends RefCounted
## Optional stamp mapping for the normal Brush pipeline. Coverage remains native
## brush ink; only local texture coordinates differ, so live edits remain lossless.
## Map allocation is capped at 2048 pixels per axis and cropped on commit.
var value: KiwiTextureMaterial
var coordinates: Image
var texture: ImageTexture
var coordinate_size:=Vector2i.ZERO
var source_size:=Vector2i.ZERO
var bounds:=Rect2i()
var distance:=0.0
var started:=false
var direction:=0.0
var tail_backup: Image
var tail_area:=Rect2i()

func begin(canvas: KiwiImageCanvas,material: KiwiTextureMaterial) -> void:
	value=material.copy_material()
	source_size=canvas._paint_image.get_size()
	var ratio:=minf(1.0,2048.0/maxi(source_size.x,source_size.y))
	coordinate_size=Vector2i((Vector2(source_size)*ratio).ceil()).max(Vector2i.ONE)
	coordinates=Image.create(coordinate_size.x,coordinate_size.y,false,Image.FORMAT_RGF)
	texture=ImageTexture.create_from_image(coordinates)
	canvas._material_region.coordinates=texture

func interval(canvas: KiwiImageCanvas) -> float:
	return maxf(1.0,canvas.brush_size*value.spacing)

func radius_factor() -> float:
	return 1.0+value.random_scale+2.0*value.jitter if value.application=="scatter" else 1.0+value.random_scale

func paint_line(canvas: KiwiImageCanvas,from: Vector2,to: Vector2,upload: bool) -> void:
	var length:=from.distance_to(to)
	if length>.001:
		var inverse:=canvas.document.world_transform(canvas._paint_layer).affine_inverse()
		direction=((inverse*to)-(inverse*from)).angle()
	if from.is_equal_approx(to):
		dab(canvas,from); started=true
	elif not started:
		dab(canvas,from); started=true
	if length>.001:
		var travel:=interval(canvas)-distance
		while travel<=length:
			dab(canvas,from.lerp(to,travel/length)); travel+=interval(canvas)
		distance=fmod(distance+length,interval(canvas))
	if upload: canvas._upload_native_paint()

func dab(canvas: KiwiImageCanvas,point: Vector2) -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=hash([point,value.parameters.get("seed",0)])
	var at:=point
	if value.application=="scatter": at+=Vector2(rng.randf_range(-1,1),rng.randf_range(-1,1))*canvas.brush_size*value.jitter
	var angle:=deg_to_rad(rng.randf_range(-1,1)*value.random_rotation)+(direction if value.follow_direction else 0.0)
	var scale:=maxf(.1,1.0+rng.randf_range(-1,1)*value.random_scale)
	var inverse:=canvas.document.world_transform(canvas._paint_layer).affine_inverse()
	var ratio:=Vector2(source_size)/canvas._paint_layer.dimensions
	var center:=inverse*at
	var size:=Vector2i((Vector2.ONE*canvas.brush_size*scale*ratio).ceil()).max(Vector2i.ONE)
	var stamp: Image=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").stamp(maxi(size.x,size.y),1.0-canvas.hardness)
	if stamp.get_size()!=size: stamp.resize(size.x,size.y,Image.INTERPOLATE_BILINEAR)
	var origin:=Vector2i(center*ratio)-size/2
	canvas._stroke_ink.blend_rect(stamp,Rect2i(Vector2i.ZERO,size),origin-canvas._ink_origin)
	var area:=Rect2i(origin,size).intersection(Rect2i(Vector2i.ZERO,source_size))
	if not area.has_area(): return
	canvas._stroke_dirty=area if not canvas._stroke_dirty.has_area() else canvas._stroke_dirty.merge(area)
	var target:=map_area(area.grow(2))
	bounds=target if not bounds.has_area() else bounds.merge(target)
	var texel_scale:=Vector2(source_size)/Vector2(coordinate_size)
	for y in range(target.position.y,target.end.y):
		for x in range(target.position.x,target.end.x):
			var pixel:=(Vector2(x,y)+Vector2.ONE*.5)*texel_scale
			if ((pixel-center*ratio)/(Vector2(size)*.5)).length()>1.02: continue
			var local:=(pixel/ratio-center).rotated(-angle)/scale+Vector2.ONE*value.texture_size*.5
			coordinates.set_pixel(x,y,Color(local.x,local.y,0,1))

func map_area(source: Rect2i) -> Rect2i:
	var scale:=Vector2(coordinate_size)/Vector2(source_size)
	var start:=Vector2i((Vector2(source.position)*scale).floor())
	var end:=Vector2i((Vector2(source.end)*scale).ceil())
	return Rect2i(start,end-start).intersection(Rect2i(Vector2i.ZERO,coordinate_size))

func restore_tail() -> void:
	if tail_backup!=null:
		coordinates.blit_rect(tail_backup,Rect2i(Vector2i.ZERO,tail_backup.get_size()),tail_area.position)
		tail_backup=null

func capture_tail(area: Rect2i) -> void:
	tail_area=map_area(area)
	if tail_area.has_area(): tail_backup=coordinates.get_region(tail_area)

func upload(region: KiwiLivePaintRegion) -> void:
	texture.update(coordinates); region.coordinates=texture

func commit(region: KiwiLivePaintRegion) -> void:
	if not bounds.has_area(): return
	region.coordinates=ImageTexture.create_from_image(coordinates.get_region(bounds))
	region.coordinate_rect=Rect2(Vector2(bounds.position)/Vector2(coordinate_size),Vector2(bounds.size)/Vector2(coordinate_size))
	tail_backup=null
