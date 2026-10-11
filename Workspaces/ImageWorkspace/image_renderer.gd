class_name KiwiImageRenderer
extends Node
## GPU composition. Each layer has a source, optional mask, and ordered effects.

const PAD := 48
const EFFECT_CODE := """shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform int mode = 0;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.7);
uniform vec4 tint2 : source_color = vec4(1.0);
uniform vec2 offset = vec2(8.0);
uniform sampler2D layer_mask : hint_default_white;
uniform bool masked = false;
uniform vec2 content_size = vec2(1280.0, 720.0);
uniform bool clipped = false;
uniform sampler2D clip_texture;
uniform vec2 clip_origin;
uniform vec2 clip_axis_x = vec2(1.0,0.0);
uniform vec2 clip_axis_y = vec2(0.0,1.0);
uniform vec2 clip_size = vec2(1280.0,720.0);
uniform float clip_opacity = 1.0;
uniform sampler2D curve_lut;
uniform vec2 yaw = vec2(0.0);
void fragment() {
 vec2 sample_uv = UV;
 bool outside = false;
 if (mode == 12 && length(yaw) > 0.00001) {
  float cy=cos(yaw.y), sy=sin(yaw.y), cx=cos(yaw.x), sx=sin(yaw.x);
  vec2 depth=vec2(-sy,cy*sx)/2.0;
  float fit=1.0+dot(abs(depth),vec2(0.5));
  vec2 q=((UV/TEXTURE_PIXEL_SIZE-vec2(48.0))/content_size-vec2(0.5))*fit;
  mat2 solve=mat2(vec2(cy,0.0)-q*depth.x,vec2(sy*sx,cx)-q*depth.y);
  vec2 p=inverse(solve)*q;
  sample_uv=((p+vec2(0.5))*content_size+vec2(48.0))*TEXTURE_PIXEL_SIZE;
  outside=any(lessThan(sample_uv,vec2(0.0))) || any(greaterThan(sample_uv,vec2(1.0)));
 }
 vec4 c = outside ? vec4(0.0) : texture(TEXTURE, sample_uv);
 c.rgb /= max(c.a, .00001);
 if (mode == 0 && masked) {
  vec2 p = (UV / TEXTURE_PIXEL_SIZE - vec2(48.0)) / content_size;
  c.a *= texture(layer_mask, clamp(p, vec2(0.0), vec2(1.0))).r;
 } else if (mode == 1) { c.rgb = clamp(c.rgb + amount, vec3(0.0), vec3(1.0));
 } else if (mode == 2) { c.rgb = clamp((c.rgb - .5) * amount + .5, vec3(0.0), vec3(1.0));
 } else if (mode == 3) { float l = dot(c.rgb, vec3(.2126,.7152,.0722)); c.rgb = clamp(mix(vec3(l), c.rgb, amount), vec3(0.0), vec3(1.0));
 } else if (mode == 4) {
  vec4 sum = vec4(0.0); float alpha = 0.0;
  for(int x=-2; x<=2; x++) { for(int y=-2; y<=2; y++) {
   vec4 s = texture(TEXTURE, UV + vec2(float(x),float(y)) * TEXTURE_PIXEL_SIZE * amount * .5);
   sum.rgb += s.rgb; alpha += s.a;
  }} c = vec4(sum.rgb / max(alpha,.00001), alpha / 25.0);
 } else if (mode == 5 || mode == 6 || mode == 9) {
  float a = 0.0;
  for(int x=-2; x<=2; x++) { for(int y=-2; y<=2; y++) {
   vec2 delta = vec2(float(x),float(y)) * amount * .5 - (mode == 6 ? offset : vec2(0.0));
   float sample_alpha = texture(TEXTURE, UV + delta * TEXTURE_PIXEL_SIZE).a;
   a = mode == 9 ? a + sample_alpha / 25.0 : max(a, sample_alpha);
  }}
  float behind = a * tint.a * (1.0-c.a); float total = c.a + behind;
  c = vec4((c.rgb*c.a + tint.rgb*behind)/max(total,.00001),total);
 } else if (mode == 7) { c.rgb = vec3(dot(c.rgb,vec3(.2126,.7152,.0722)));
 } else if (mode == 8) { c.rgb = vec3(1.0)-c.rgb;
 } else if (mode == 10) {
  c = texture(TEXTURE,UV+vec2(sin(UV.y*20.0)*amount*TEXTURE_PIXEL_SIZE.x,0.0));
  c.rgb /= max(c.a,.00001);
 } else if (mode == 11) {
  c.rgb = vec3(texture(curve_lut,vec2(c.r,.5)).r,texture(curve_lut,vec2(c.g,.5)).r,texture(curve_lut,vec2(c.b,.5)).r);
 } else if (mode == 13) {
  vec3 n=texture(TEXTURE,UV+vec2(0.0,-1.0)*TEXTURE_PIXEL_SIZE).rgb;
  vec3 s=texture(TEXTURE,UV+vec2(0.0,1.0)*TEXTURE_PIXEL_SIZE).rgb;
  vec3 e=texture(TEXTURE,UV+vec2(1.0,0.0)*TEXTURE_PIXEL_SIZE).rgb;
  vec3 w=texture(TEXTURE,UV+vec2(-1.0,0.0)*TEXTURE_PIXEL_SIZE).rgb;
  c.rgb=clamp(c.rgb*(1.0+4.0*amount)-(n+s+e+w)*amount,vec3(0.0),vec3(1.0));
 } else if (mode == 14) {
  vec2 block=max(vec2(1.0),vec2(amount))*TEXTURE_PIXEL_SIZE;
  c=texture(TEXTURE,(floor(UV/block)+.5)*block); c.rgb/=max(c.a,.00001);
 } else if (mode == 15) {
  float noise=fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453)-.5;
  c.rgb=clamp(c.rgb+noise*amount,vec3(0.0),vec3(1.0));
 } else if (mode == 16) {
  vec2 shift=vec2(amount,0.0)*TEXTURE_PIXEL_SIZE;
  c.r=texture(TEXTURE,UV+shift).r/max(texture(TEXTURE,UV+shift).a,.00001);
  c.b=texture(TEXTURE,UV-shift).b/max(texture(TEXTURE,UV-shift).a,.00001);
 } else if (mode == 17) {
  float l=dot(c.rgb,vec3(.2126,.7152,.0722));
  vec2 cell=fract(FRAGCOORD.xy/max(2.0,amount))-.5;
  c.rgb=vec3(step(length(cell),sqrt(clamp(l,0.0,1.0))*.7));
 } else if (mode == 18) {
  c.rgb=floor(c.rgb*max(2.0,amount))/(max(2.0,amount)-1.0);
 } else if (mode == 19) {
  vec2 p=UV*2.0-1.0; c.rgb*=1.0-clamp(dot(p,p)*amount,0.0,.95);
 } else if (mode == 20) {
  float l=dot(c.rgb,vec3(.2126,.7152,.0722)); c.rgb=mix(tint.rgb,tint2.rgb,l);
 } else if (mode == 21) {
  float similarity=1.0-smoothstep(max(.001,amount),max(.002,amount*1.6),distance(c.rgb,tint.rgb));
  c.rgb=mix(c.rgb,tint2.rgb,similarity*tint2.a);
 } else if (mode == 22) {
  vec2 p=UV-.5; float radius=length(p); float angle=atan(p.y,p.x)+amount*(.5-radius);
  c=texture(TEXTURE,vec2(cos(angle),sin(angle))*radius+.5); c.rgb/=max(c.a,.00001);
 }
 if (mode == 0 && clipped) {
  vec2 p = UV / TEXTURE_PIXEL_SIZE - vec2(48.0);
  vec2 uv = (clip_origin + clip_axis_x*p.x + clip_axis_y*p.y + vec2(48.0))/clip_size;
  c.a *= (uv.x>=0.0 && uv.y>=0.0 && uv.x<=1.0 && uv.y<=1.0) ? texture(clip_texture,uv).a * clip_opacity : 0.0;
 }
 COLOR = vec4(c.rgb*c.a,c.a);
}
"""

class LayerDrawing extends Node2D:
	var layer: KiwiImageLayer
	var text_detail:=1.0
	var font: Font
	var font_key := ""
	var gradient: GradientTexture2D
	var noise: NoiseTexture2D
	var noise_key := 0
	func _draw() -> void:
		if layer == null: return
		var p: Dictionary = layer.properties
		var rect := Rect2(Vector2.ZERO, layer.dimensions)
		var color: Color = p.get("color", Color.WHITE)
		match layer.kind:
			"image", "paint", "basic":
				if layer.texture != null: draw_texture_rect(layer.texture, rect, false)
			"shape":
				var stroke: float = p.get("stroke", 0.0)
				var stroke_color: Color = p.get("stroke_color", Color.WHITE)
				var filled:=bool(p.get("filled",true))
				if p.get("shape", "rectangle") in ["triangle","custom"]:
					var points: PackedVector2Array=PackedVector2Array([Vector2(layer.dimensions.x*.5,0),layer.dimensions,Vector2(0,layer.dimensions.y)]) if p.shape=="triangle" else p.get("points",PackedVector2Array())
					if p.shape=="custom":
						points=points.duplicate()
						for index in points.size(): points[index]*=layer.dimensions/Vector2(p.get("path_size",layer.dimensions)).max(Vector2.ONE)
						points=KiwiImageLayer.rounded_polygon(points,float(p.get("radius",0)))
					if filled and points.size()>=3:
						var triangles:=Geometry2D.triangulate_polygon(points)
						for index in range(0,triangles.size(),3): draw_colored_polygon(PackedVector2Array([points[triangles[index]],points[triangles[index+1]],points[triangles[index+2]]]),color)
					if stroke>0 and points.size()>1: points.append(points[0]); draw_polyline(points,stroke_color,stroke,true)
					return
				if p.get("shape", "rectangle") == "ellipse":
					var points := PackedVector2Array()
					for i in 96: points.append(layer.dimensions * .5 + Vector2(cos(TAU*i/96.0),sin(TAU*i/96.0))*layer.dimensions*.5)
					if filled: draw_colored_polygon(points,color)
					if stroke > 0: points.append(points[0]); draw_polyline(points,stroke_color,stroke,true)
				else:
					var box := StyleBoxFlat.new()
					box.bg_color = color
					box.draw_center=filled
					box.set_corner_radius_all(int(p.get("radius", 24)))
					box.set_border_width_all(int(stroke))
					box.border_color = stroke_color
					draw_style_box(box, rect)
			"text":
				var settings:=ActorTextSettings.values(p.get("text_settings"))
				if settings.is_empty(): settings=p
				var key := str(settings.get("font", "")) + str(settings.get("bold", false))+str(settings.get("italic",false))+str(settings.get("letter_spacing",0))+str(settings.get("line_spacing",0))
				if font == null or font_key != key:
					var base:=ActorTextSettings.font(settings)
					if int(settings.get("letter_spacing",0))!=0 or int(settings.get("line_spacing",0))!=0:
						var variation:=FontVariation.new(); variation.base_font=base
						variation.spacing_glyph=int(settings.get("letter_spacing",0)); variation.spacing_space=int(settings.get("letter_spacing",0))
						variation.spacing_top=int(settings.get("line_spacing",0)/2); variation.spacing_bottom=int(settings.get("line_spacing",0)/2); font=variation
					else: font=base
					font_key = key
				var font_size: int = maxi(1,roundi(float(settings.get("font_size",72))*float(p.get("text_scale",1.0))*text_detail))
				draw_set_transform(Vector2.ZERO,0,Vector2.ONE/text_detail)
				var alignment: int = p.get("alignment",0)
				var pos := Vector2(0,font.get_ascent(font_size))
				if int(settings.get("outline_size",0)) > 0:
					draw_multiline_string_outline(font,pos,str(p.get("text","Text")),alignment,layer.dimensions.x*text_detail,font_size,-1,roundi(float(settings.get("outline_size",0))*text_detail),settings.get("outline_color",Color.BLACK))
				if bool(settings.get("shadow",false)):
					draw_multiline_string(font,pos+Vector2(settings.get("shadow_offset",Vector2(2,2)))*float(p.get("text_scale",1.0))*text_detail,str(p.get("text","Text")),alignment,layer.dimensions.x*text_detail,font_size,-1,settings.get("shadow_color",Color(0,0,0,.65)))
				draw_multiline_string(font,pos,str(p.get("text","Text")),alignment,layer.dimensions.x*text_detail,font_size,-1,settings.get("color",color))
				draw_set_transform(Vector2.ZERO)
			"gradient":
				if gradient == null: gradient = GradientTexture2D.new()
				var ramp := Gradient.new()
				ramp.colors = PackedColorArray([color,p.get("color_end",Color.WHITE)])
				gradient.gradient = ramp
				gradient.fill = GradientTexture2D.FILL_RADIAL if bool(p.get("gradient_radial",false)) else GradientTexture2D.FILL_LINEAR
				var direction := Vector2.from_angle(deg_to_rad(float(p.get("gradient_angle",0))))*.5
				gradient.fill_from = Vector2(.5,.5)-direction
				gradient.fill_to = Vector2(.5,.5)+direction
				draw_texture_rect(gradient,rect,false)
			"noise":
				if layer.texture != null:
					draw_texture_rect(layer.texture,rect,false)
					return
				if noise == null:
					noise=NoiseTexture2D.new()
					noise.width=512; noise.height=512
					noise.changed.connect(queue_redraw)
				if noise_key != p.hash():
					noise_key=p.hash()
					var generator:=FastNoiseLite.new()
					generator.seed=int(p.get("noise_seed",0))
					generator.frequency=float(p.get("noise_frequency",.02))
					generator.fractal_octaves=int(p.get("noise_octaves",5))
					noise.noise=generator
					var ramp:=Gradient.new(); ramp.colors=PackedColorArray([color,p.get("color_end",Color.WHITE)])
					noise.color_ramp=ramp
					noise.as_normal_map=bool(p.get("noise_normal",false))
				draw_texture_rect(noise,rect,false)
			"path":
				var points: PackedVector2Array = p.get("points",PackedVector2Array())
				var path_size: Vector2 = p.get("path_size",layer.dimensions)
				for index in points.size(): points[index] *= layer.dimensions / path_size.max(Vector2.ONE)
				if points.size() >= 3: draw_colored_polygon(points,color)
				if points.size() >= 2 and float(p.get("stroke",0)) > 0:
					points.append(points[0]); draw_polyline(points,p.get("stroke_color",Color.WHITE),float(p.stroke),true)

var viewport := SubViewport.new()
var export_viewport := SubViewport.new()
var _export_display := TextureRect.new()
var document: KiwiImageDocument
var views: Dictionary = {}
var _topology := ""
var _shader := Shader.new()
var _straight_shader := Shader.new()
var render_scale := 1.0
var exporting := false
var preview_size:=Vector2i.ZERO
var preview_transform:=Transform2D.IDENTITY


func _ready() -> void:
	_shader.code = EFFECT_CODE
	viewport.transparent_bg = true
	viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_straight_shader.code = "shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment() { vec4 c = texture(TEXTURE, UV); COLOR = vec4(c.rgb / max(c.a, 0.00001), c.a); }"
	export_viewport.transparent_bg = true
	export_viewport.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	export_viewport.disable_3d = true
	export_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(export_viewport)
	_export_display.texture = viewport.get_texture()
	var straight := ShaderMaterial.new(); straight.shader = _straight_shader
	_export_display.material = straight
	export_viewport.add_child(_export_display)


func _surface(dimensions: Vector2i) -> SubViewport:
	var target := SubViewport.new()
	target.size = dimensions.max(Vector2i.ONE)
	target.transparent_bg = true
	target.render_target_clear_mode=SubViewport.CLEAR_MODE_ALWAYS
	target.disable_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(target)
	return target


func sync(value: KiwiImageDocument) -> void:
	document = value
	viewport.size = preview_size if preview_size!=Vector2i.ZERO and not exporting else Vector2i((Vector2(document.canvas_size)*render_scale).round().max(Vector2.ONE))
	viewport.canvas_transform=preview_transform if not exporting else Transform2D.IDENTITY
	export_viewport.size = viewport.size
	_export_display.size = Vector2(viewport.size)
	var topology := ""
	for layer in document.layers:
		topology += layer.id + layer.parent_id + layer.kind
		for effect in layer.effects: topology += str(effect.get("id", "")) + str(effect.get("type", "")) + str(effect.get("shader", ""))
	if topology != _topology:
		_topology = topology
		for child in get_children():
			if child != viewport and child != export_viewport: remove_child(child); child.queue_free()
		for child in viewport.get_children(): viewport.remove_child(child); child.queue_free()
		views.clear()
		for layer in document.children(): _build_layer(layer, viewport)
	for layer in document.layers:
		if views.has(layer.id): _update_layer(layer, views[layer.id])


func _build_layer(layer: KiwiImageLayer, parent: Node) -> void:
	var target_size := Vector2i((_content_dimensions(layer)*render_scale).ceil()) + Vector2i.ONE * PAD * 2
	var base := _surface(target_size)
	var drawing := LayerDrawing.new()
	drawing.layer = layer
	drawing.position = Vector2.ONE * PAD
	base.add_child(drawing)
	var stages: Array[Dictionary] = []
	var previous := base
	var mask := {"type":"mask"}
	var effects: Array = [mask] + layer.effects + [{"type":"values"},{"type":"perspective"}]
	for effect: Dictionary in effects:
		var input_surface: SubViewport
		var input_display: TextureRect
		if effect.get("type", "") == "shader":
			input_surface = _surface(target_size)
			input_display = TextureRect.new()
			input_display.texture = previous.get_texture()
			input_display.size = Vector2(target_size)
			var unpremultiply := ShaderMaterial.new(); unpremultiply.shader = _straight_shader
			input_display.material = unpremultiply
			input_surface.add_child(input_display)
			previous = input_surface
		var surface := _surface(target_size)
		var display := TextureRect.new()
		display.texture = previous.get_texture()
		display.size = Vector2(target_size)
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		if effect.get("type", "") == "shader" and effect.get("shader") is Shader:
			material.shader = effect.shader
		else: material.shader = _shader
		display.material = material
		surface.add_child(display)
		stages.append({"viewport":surface,"display":display,"material":material,"input_viewport":input_surface,"input_display":input_display})
		previous = surface
	var root := Node2D.new()
	parent.add_child(root)
	var output := Sprite2D.new()
	output.centered = false
	output.texture = previous.get_texture()
	output.position = -Vector2.ONE * PAD
	root.add_child(output)
	var direct_text:=LayerDrawing.new()
	direct_text.visible=false
	root.add_child(direct_text)
	var blending := CanvasItemMaterial.new()
	output.material = blending
	views[layer.id] = {"root":root,"output":output,"direct_text":direct_text,"base":base,"drawing":drawing,"stages":stages,"blend":blending,"signature":0,"allocated_dimensions":layer.dimensions}
	for child in document.children(layer.id): _build_layer(child,root)


func _update_layer(layer: KiwiImageLayer, view: Dictionary) -> void:
	var transform:=layer.local_transform()
	transform.origin*=render_scale
	view.root.transform = transform
	view.root.visible = layer.visible
	view.output.modulate = Color(layer.opacity,layer.opacity,layer.opacity,layer.opacity) if layer.blend==0 else Color(1,1,1,layer.opacity)
	view.output.scale=Vector2.ONE
	view.output.position=-Vector2.ONE*PAD
	view.blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA if layer.blend==0 else layer.blend
	# Plain text is drawn directly: resizing must not recreate a chain of render targets.
	var direct: bool=layer.kind=="text" and layer.blend==0 and layer.effects.is_empty() and preload("res://Workspaces/ImageWorkspace/image_values.gd").operations(layer).is_empty() and layer.mask==null and not layer.clip_to_below and is_zero_approx(float(layer.properties.get("yaw_up_down",0))) and is_zero_approx(float(layer.properties.get("yaw_left_right",0)))
	view.direct_text.visible=direct and document.isolation_allows(layer)
	view.output.visible=not direct and document.isolation_allows(layer)
	if direct:
		view.direct_text.layer=layer
		view.direct_text.scale=Vector2.ONE*render_scale
		view.direct_text.modulate=Color(1,1,1,layer.opacity)
		view.direct_text.queue_redraw()
		view.drawing.layer=layer; view.drawing.queue_redraw()
		return
	var target_size := Vector2i((_content_dimensions(layer)*render_scale).ceil()) + Vector2i.ONE * PAD * 2
	# Reflow live text into a stable surface. Reallocating the dependent targets
	# every mouse event clears the GPU chain and flashes black between frames.
	var stable: bool=layer.kind=="text" and bool(view.get("stable_text_surface",false)) and not exporting
	if stable: target_size=view.base.size
	view.base.size = target_size.max(Vector2i.ONE)
	var raster_scale:=Vector2(target_size-Vector2i.ONE*PAD*2)/_content_dimensions(layer).max(Vector2.ONE)
	view.drawing.layer = layer
	view.drawing.scale = raster_scale if stable else Vector2.ONE * (1.0 if layer.kind=="group" else render_scale)
	if stable:
		view.output.scale=Vector2.ONE*render_scale/raster_scale
		view.output.position=-Vector2.ONE*PAD*view.output.scale
	var signature := hash([layer.dimensions,layer.properties,layer.texture,render_scale])
	if int(view.signature) != signature or layer.kind=="text":
		view.signature = signature
		view.drawing.queue_redraw()
	var effects: Array = [{"type":"mask","enabled":true}] + layer.effects + [{"type":"values"},{"type":"perspective"}]
	var modes := {"mask":0,"brightness":1,"contrast":2,"saturation":3,"blur":4,"outline":5,"shadow":6,"grayscale":7,"invert":8,"glow":9,"wave":10,"curves":11,"perspective":12,
		"sharpen":13,"pixelate":14,"grain":15,"chromatic":16,"halftone":17,"posterize":18,"vignette":19,"gradient_map":20,"color_replace":21,"twirl":22}
	for index in view.stages.size():
		var stage: Dictionary = view.stages[index]
		var effect: Dictionary = effects[index]
		stage.viewport.size = target_size.max(Vector2i.ONE)
		stage.display.size = Vector2(target_size)
		if stage.input_viewport != null:
			stage.input_viewport.size = target_size.max(Vector2i.ONE)
			stage.input_display.size = Vector2(target_size)
		var material: ShaderMaterial = stage.material
		var enabled := bool(effect.get("enabled",true))
		if effect.get("type","") == "values":
			var code: String=preload("res://Workspaces/ImageWorkspace/image_values.gd").shader_code(layer)
			if stage.get("values_code","")!=code:
				var shader:=Shader.new(); shader.code=code; material.shader=shader; stage.values_code=code
			var mapping:=document.world_transform(layer)
			if layer.properties.has("values_selection_frame"):
				mapping=Transform2D(layer.properties.values_selection_frame).scaled_local(Vector2(layer.properties.get("values_selection_dimensions",layer.dimensions))/layer.dimensions.max(Vector2.ONE))
			material.set_shader_parameter("selection_only",bool(layer.properties.get("values_selection_only",false)))
			material.set_shader_parameter("selection_mask",layer.properties.get("values_selection"))
			material.set_shader_parameter("has_selection",layer.properties.get("values_selection")!=null)
			material.set_shader_parameter("selection_origin",mapping.origin)
			material.set_shader_parameter("selection_x",mapping.x/(raster_scale.x if stable else render_scale))
			material.set_shader_parameter("selection_y",mapping.y/(raster_scale.y if stable else render_scale))
			material.set_shader_parameter("document_size",Vector2(document.canvas_size))
			material.set_shader_parameter("content_extent",_content_dimensions(layer)*(raster_scale if stable else Vector2.ONE*render_scale))
		elif effect.get("type","") == "shader":
			stage.display.material = material if enabled else null
			for key in effect.get("uniforms",{}): material.set_shader_parameter(key,effect.uniforms[key])
		else:
			material.set_shader_parameter("mode",int(modes.get(effect.get("type",""),0)) if enabled else 0)
			material.set_shader_parameter("masked",index == 0 and layer.mask != null)
			material.set_shader_parameter("layer_mask",layer.mask)
			material.set_shader_parameter("content_size",layer.dimensions*(raster_scale if stable else Vector2.ONE*render_scale))
			material.set_shader_parameter("yaw",Vector2(deg_to_rad(float(layer.properties.get("yaw_up_down",0))),deg_to_rad(float(layer.properties.get("yaw_left_right",0)))))
			material.set_shader_parameter("amount",float(effect.get("amount",1.0))*(render_scale if effect.get("type","") in ["blur","outline","shadow","glow","wave","chromatic","pixelate","halftone"] else 1.0))
			material.set_shader_parameter("tint",effect.get("color",Color(0,0,0,.7)))
			material.set_shader_parameter("tint2",effect.get("color2",Color.WHITE))
			material.set_shader_parameter("offset",effect.get("offset",Vector2(8,8))*render_scale)
			if effect.get("curve") is Curve:
				if not stage.has("curve_texture"):
					stage.curve_texture=CurveTexture.new()
					stage.curve_texture.width=256
				stage.curve_texture.curve=effect.curve
				material.set_shader_parameter("curve_lut",stage.curve_texture)
			material.set_shader_parameter("clipped",index==0 and layer.clip_to_below)
			if index==0 and layer.clip_to_below:
				var siblings:=document.children(layer.parent_id)
				var previous:=siblings.find(layer)-1
				if previous>=0 and views.has(siblings[previous].id):
					var below: KiwiImageLayer=siblings[previous]
					var mapping:=document.world_transform(below).affine_inverse()*document.world_transform(layer)
					material.set_shader_parameter("clip_texture",views[below.id].output.texture)
					material.set_shader_parameter("clip_origin",mapping.origin*render_scale)
					material.set_shader_parameter("clip_axis_x",mapping.x)
					material.set_shader_parameter("clip_axis_y",mapping.y)
					material.set_shader_parameter("clip_size",below.dimensions*render_scale+Vector2.ONE*PAD*2)
					material.set_shader_parameter("clip_opacity",below.opacity if below.visible else 0.0)
				else: material.set_shader_parameter("clipped",false)
	view.allocated_dimensions=layer.dimensions


func sync_transforms(value: KiwiImageDocument) -> void:
	document=value
	for layer in document.layers:
		if not views.has(layer.id): continue
		var view: Dictionary=views[layer.id]
		if layer.kind=="text":
			view.stable_text_surface=true
			_update_layer(layer,view)
			continue
		var transform:=layer.local_transform(); transform.origin*=render_scale; view.root.transform=transform
		var allocated: Vector2=view.get("allocated_dimensions",layer.dimensions)
		var preview_scale:=layer.dimensions/allocated.max(Vector2.ONE)
		view.output.scale=preview_scale
		view.output.position=-Vector2.ONE*PAD*preview_scale
		view.output.modulate=Color(layer.opacity,layer.opacity,layer.opacity,layer.opacity) if layer.blend==0 else Color(1,1,1,layer.opacity)


func texture() -> Texture2D:
	return viewport.get_texture()


func _content_dimensions(layer: KiwiImageLayer) -> Vector2:
	return layer.content_dimensions()


func set_enabled(enabled: bool) -> void:
	for child in get_children():
		if child is SubViewport: child.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED


func flattened() -> Image:
	exporting=true
	var previous_scale:=render_scale
	render_scale=1.0
	sync(document)
	set_enabled(true)
	# Group sources can depend on several other offscreen passes. Wait for the
	# longest actual dependency chain, including custom shader input conversion.
	var frames:=3
	for layer in document.layers:
		var passes:=2
		var current: KiwiImageLayer=layer
		while current!=null:
			passes+=4+current.effects.size()
			for effect in current.effects:
				if effect.get("type","")=="shader": passes+=1
			current=document.layer_for_id(current.parent_id)
		frames=maxi(frames,passes)
	for frame in frames: await RenderingServer.frame_post_draw
	var image:=export_viewport.get_texture().get_image()
	exporting=false
	render_scale=previous_scale
	sync(document)
	return image


func set_preview_scale(requested: float) -> void:
	if exporting or document==null: return
	for layer in document.layers:
		if layer.kind!="text" or not views.has(layer.id): continue
		var drawing: LayerDrawing=views[layer.id].direct_text
		var world:=document.world_transform(layer)
		var detail:=maxf(1,requested*maxf(world.x.length(),world.y.length()))
		if not is_equal_approx(drawing.text_detail,detail): drawing.text_detail=detail; drawing.queue_redraw()


func set_preview_camera(dimensions: Vector2, origin: Vector2, zoom: float) -> void:
	if exporting: return
	preview_size=Vector2i(dimensions.ceil()).max(Vector2i.ONE)
	preview_transform=Transform2D(0,origin).scaled_local(Vector2.ONE*zoom)
	viewport.size=preview_size
	viewport.canvas_transform=preview_transform
	set_preview_scale(zoom)
