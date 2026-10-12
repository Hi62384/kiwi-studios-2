extends RefCounted
## Deterministic pattern arrangements. Texture synthesis is a separate algorithm.
static func sample(source: Image,area: Rect2i,point: Vector2,settings: Dictionary) -> Color:
	if not area.has_area(): return Color.TRANSPARENT
	var scale:=maxf(.01,float(settings.get("scale",1)))
	var p: Vector2=(point-Vector2(settings.get("offset",Vector2.ZERO))).rotated(-deg_to_rad(float(settings.get("rotation",0))))/scale
	var spacing:=maxf(0,float(settings.get("spacing",0)))
	var cell_size:=Vector2(area.size)*(1+spacing)
	var cell:=Vector2i((p/cell_size).floor())
	var local:=p-Vector2(cell)*cell_size
	var layout: String=str(settings.get("layout","tiled"))
	if layout=="offset" and posmod(cell.y,2)==1:
		p.x+=cell_size.x*.5; cell.x=floori(p.x/cell_size.x); local=p-Vector2(cell)*cell_size
	var rng:=RandomNumberGenerator.new(); rng.seed=hash([cell,settings.get("seed",0)])
	if rng.randf()>float(settings.get("density",1)): return Color.TRANSPARENT
	if layout=="scatter": local-=Vector2(rng.randf_range(-.35,.35),rng.randf_range(-.35,.35))*cell_size
	var natural:=str(settings.get("behavior","exact"))=="natural"
	var variation:=float(settings.get("variation",1))
	if natural:
		local=(local-Vector2(area.size)*.5).rotated(deg_to_rad(rng.randf_range(-1,1)*float(settings.get("random_rotation",15))*variation))/maxf(.1,1+rng.randf_range(-1,1)*float(settings.get("random_scale",.15))*variation)+Vector2(area.size)*.5
	if local.x<0 or local.y<0 or local.x>=area.size.x or local.y>=area.size.y: return Color.TRANSPARENT
	if not preload("res://Workspaces/ImageWorkspace/image_texture_synthesis.gd").inside_sample(Vector2(area.position)+local,area,settings): return Color.TRANSPARENT
	var color:=source.get_pixelv(area.position+Vector2i(local))
	if natural:
		var gain:=1+rng.randf_range(-1,1)*float(settings.get("color_variation",.1))*variation; color.r*=gain; color.g*=gain; color.b*=gain
	return color
