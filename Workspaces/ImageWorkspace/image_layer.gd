class_name KiwiImageLayer
extends Resource
## Serializable, independently editable content. Raster sources retain their resolution.

@export var id: String = ""
@export var label: String = "Layer"
@export var kind: String = "paint"
@export var parent_id: String = ""
@export var position := Vector2.ZERO
@export var dimensions := Vector2(400, 300)
@export var rotation: float = 0.0
@export var visible: bool = true
@export var isolated: bool = false
@export var locked: bool = false
@export var opacity: float = 1.0
@export var blend: int = 0
@export var clip_to_below: bool = false
@export var texture: Texture2D
@export var paint_base: Texture2D
@export var mask: Texture2D
@export var effects: Array[Dictionary] = []
@export var properties: Dictionary = {}
@export var warp: KiwiImageWarpData


static func create(type: String, canvas_size: Vector2i) -> KiwiImageLayer:
	var layer := KiwiImageLayer.new()
	layer.id = ActorData.new_id()
	layer.kind = type
	layer.label = type.capitalize()
	layer.dimensions = Vector2(canvas_size)
	layer.properties = {"color": Color("62d9bc"), "color_end": Color("4666ea"),
		"shape": "rectangle", "radius": 24.0, "stroke": 0.0, "stroke_color": Color.WHITE,
		"text": "Your story,\nyour canvas.", "font": "", "font_size": 72,
		"bold": false, "alignment": 0, "outline": 0, "outline_color": Color("132334"),
		"points": PackedVector2Array(), "gradient_angle": 0.0, "gradient_radial": false,
		"filled":true,"keep_aspect": type == "image"}
	if type in ["shape", "text", "path"]:
		layer.dimensions = Vector2(420, 240)
		layer.position = (Vector2(canvas_size) - layer.dimensions) * 0.5
	if type == "text":
		layer.properties.color=Color.WHITE
		var settings:=ActorObjectData.new(); settings.type_id=&"text_settings"
		settings.values={&"font":"Arial",&"font_size":72.0,&"bold":false,&"italic":false,&"color":Color.WHITE,
			&"letter_spacing":0,&"line_spacing":0,&"outline_size":0,&"outline_color":Color("132334"),&"shadow":false,&"shadow_color":Color(0,0,0,.65),&"shadow_offset":Vector2(2,2)}
		layer.properties.text_settings=settings
		layer.properties.text_scale=1.0
	if type == "noise":
		var noise_object:=ActorObjectData.new(); noise_object.type_id=&"noise_image"
		noise_object.values={&"noise_type":FastNoiseLite.TYPE_SIMPLEX_SMOOTH,&"fractal_type":FastNoiseLite.FRACTAL_FBM,
			&"seed":0,&"frequency":.015,&"octaves":5,&"lacunarity":2.0,&"gain":.5,&"contrast":1.0,
			&"low_color":Color.BLACK,&"high_color":Color.WHITE,&"seamless":true,&"invert":false,
			&"as_normal_map":false,&"resolution":2}
		layer.properties.noise_object=noise_object
		layer.texture=ActorImageGenerator.texture_for_object(noise_object)
	if type in ["paint", "basic"]:
		var bitmap := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
		# Transparent black avoids white RGB leaking through filtered transparent
		# pixels while a fresh paint layer is uploaded to the renderer.
		bitmap.fill(Color(0,0,0,0))
		layer.texture = ImageTexture.create_from_image(bitmap)
		layer.paint_base = layer.texture
	return layer


static func rounded_polygon(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	if radius<=0 or points.size()<3: return points
	var result:=PackedVector2Array()
	for i in points.size():
		var corner:=points[i]; var previous:=points[posmod(i-1,points.size())]; var next:=points[(i+1)%points.size()]
		var distance:=minf(radius,minf(corner.distance_to(previous),corner.distance_to(next))*.5)
		var start:=corner.move_toward(previous,distance); var end:=corner.move_toward(next,distance)
		for step in 9:
			var t:=step/8.0
			var point:=start*(1-t)*(1-t)+corner*2*t*(1-t)+end*t*t
			if result.is_empty() or not result[-1].is_equal_approx(point): result.append(point)
	if result.size()>1 and result[0].is_equal_approx(result[-1]): result.remove_at(result.size()-1)
	return result


func local_transform() -> Transform2D:
	var half := dimensions * 0.5
	var flip:=Vector2(-1.0 if bool(properties.get("flip_x",false)) else 1.0,-1.0 if bool(properties.get("flip_y",false)) else 1.0)
	var basis:=_orientation()*Transform2D(properties.get("basis_x",Vector2.RIGHT),properties.get("basis_y",Vector2.DOWN),Vector2.ZERO)
	basis=basis.scaled_local(flip); basis.origin=position+half
	return basis*Transform2D(0.0,-half)


func _orientation() -> Transform2D:
	# Yaw is projected in the renderer; this transform remains the editing plane.
	return Transform2D(rotation,Vector2.ZERO)


func project_point(point: Vector2, extent: Vector2=Vector2(-1,-1)) -> Vector2:
	if extent.x<0: extent=dimensions
	var yaw_x:=deg_to_rad(float(properties.get("yaw_up_down",0)))
	var yaw_y:=deg_to_rad(float(properties.get("yaw_left_right",0)))
	var p: Vector2=point/extent-Vector2.ONE*.5
	var depth:=Vector2(-sin(yaw_y),cos(yaw_y)*sin(yaw_x))*.5
	var fit:=1+depth.abs().dot(Vector2.ONE*.5)
	var q:=Vector2(cos(yaw_y)*p.x+sin(yaw_y)*sin(yaw_x)*p.y,cos(yaw_x)*p.y)
	return (q/(1+depth.dot(p))/fit+Vector2.ONE*.5)*extent


func unproject_point(point: Vector2) -> Vector2:
	var x:=deg_to_rad(float(properties.get("yaw_up_down",0))); var y:=deg_to_rad(float(properties.get("yaw_left_right",0)))
	var depth:=Vector2(-sin(y),cos(y)*sin(x))*.5
	var fit:=1+depth.abs().dot(Vector2.ONE*.5)
	var q: Vector2=(point/dimensions-Vector2.ONE*.5)*fit
	var solve:=Transform2D(Vector2(cos(y),0)-q*depth.x,Vector2(sin(y)*sin(x),cos(x))-q*depth.y,Vector2.ZERO)
	return (solve.affine_inverse()*q+Vector2.ONE*.5)*dimensions


func projected_bounds(extent: Vector2=Vector2(-1,-1)) -> Rect2:
	if extent.x<0: extent=dimensions
	var bounds:=Rect2(project_point(Vector2.ZERO,extent),Vector2.ZERO)
	for uv in [Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: bounds=bounds.expand(project_point(uv*extent,extent))
	return bounds


func set_linear_basis(basis: Transform2D) -> void:
	var flip:=Vector2(-1.0 if bool(properties.get("flip_x",false)) else 1.0,-1.0 if bool(properties.get("flip_y",false)) else 1.0)
	var normalized:=_orientation().affine_inverse()*basis.scaled_local(flip)
	properties.basis_x=normalized.x; properties.basis_y=normalized.y


func content_dimensions() -> Vector2:
	if kind!="text": return dimensions
	var settings:=ActorTextSettings.values(properties.get("text_settings"))
	var font:=ActorTextSettings.font(settings)
	var font_size:=maxi(1,roundi(float(settings.get("font_size",72))*float(properties.get("text_scale",1))))
	var measured:=font.get_multiline_string_size(str(properties.get("text","")),int(properties.get("alignment",0)),dimensions.x,font_size)
	return dimensions.max(measured+Vector2.ONE*float(settings.get("outline_size",0))+Vector2(settings.get("shadow_offset",Vector2.ZERO)).abs())


func copy_layer() -> KiwiImageLayer:
	# Raster textures are immutable between gestures. Painting replaces a texture
	# before touching pixels, allowing history to share all untouched sources.
	var copy := KiwiImageLayer.new()
	for key in ["id","label","kind","parent_id","position","dimensions","rotation","visible","isolated","locked","opacity","blend","clip_to_below","texture","paint_base","mask"]:
		copy.set(key,get(key))
	copy.properties = properties.duplicate(true)
	if warp!=null: copy.warp=warp.copy_warp()
	if properties.get("texture_recipe") is KiwiImageTextureRecipe: copy.properties.texture_recipe=properties.texture_recipe.copy_recipe()
	if properties.get("texture_material") is KiwiTextureMaterial: copy.properties.texture_material=properties.texture_material.copy_material()
	if properties.get("text_settings") is ActorObjectData:
		copy.properties.text_settings=(properties.text_settings as ActorObjectData).copy_object()
	if properties.get("noise_object") is ActorObjectData:
		copy.properties.noise_object=(properties.noise_object as ActorObjectData).copy_object()
	copy.effects.assign(effects.duplicate(true))
	for effect in copy.effects:
		if effect.get("curve") is Curve: effect.curve=effect.curve.duplicate()
		for channel in effect.get("curves",{}):
			if effect.curves[channel] is Curve: effect.curves[channel]=effect.curves[channel].duplicate()
	return copy
