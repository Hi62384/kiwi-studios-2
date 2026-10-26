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
uniform int mirror_side = 0;
uniform float mirror_position = 0.5;
uniform float effect_angle = 0.0;
uniform float spacing = 12.0;
uniform vec2 blur_direction=vec2(1.0,0.0);
uniform bool preserve_color=false;
uniform sampler2D effect_original;
uniform sampler2D effect_selection;
uniform bool effects_selection_only = false;
uniform bool has_effect_selection = false;
void fragment() {
 vec2 sample_uv = UV;
 bool outside = false;
 if (mode == 23) {
  vec2 p = (UV / TEXTURE_PIXEL_SIZE - vec2(48.0)) / content_size;
  if (mirror_side == 0) p.x = mirror_position - abs(p.x - mirror_position);
  else if (mirror_side == 1) p.x = mirror_position + abs(p.x - mirror_position);
  else if (mirror_side == 2) p.y = mirror_position - abs(p.y - mirror_position);
  else p.y = mirror_position + abs(p.y - mirror_position);
  outside = any(lessThan(p,vec2(0.0))) || any(greaterThan(p,vec2(1.0)));
  sample_uv = (p * content_size + vec2(48.0)) * TEXTURE_PIXEL_SIZE;
 }
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
 if (mode == 25 || mode == 26) {
  vec2 px=TEXTURE_PIXEL_SIZE;
  vec3 dx=texture(TEXTURE,UV+vec2(px.x,0.0)).rgb-texture(TEXTURE,UV-vec2(px.x,0.0)).rgb;
  vec3 dy=texture(TEXTURE,UV+vec2(0.0,px.y)).rgb-texture(TEXTURE,UV-vec2(0.0,px.y)).rgb;
  if(mode==25 && preserve_color){float relief=dot(dx+dy,vec3(.2126,.7152,.0722))*amount; c.rgb=clamp(c.rgb*(1.0+relief*2.0),vec3(0.0),vec3(1.0));}
  else{c.rgb=mode==25 ? clamp(vec3(.5)+(dx+dy)*amount,vec3(0.0),vec3(1.0)) : clamp(sqrt(dx*dx+dy*dy)*amount*4.0,vec3(0.0),vec3(1.0));}
 } else if (mode == 27 || mode == 31) {
  vec2 direction=mode==27 ? vec2(cos(effect_angle),sin(effect_angle))*TEXTURE_PIXEL_SIZE*amount : (UV-vec2(.5))*amount*.015;
  vec4 sum=vec4(0.0);
  for(int i=-6;i<=6;i++){sum+=texture(TEXTURE,UV+direction*float(i)/6.0);}
  c=sum/13.0; c.rgb/=max(c.a,.00001);
 } else if (mode == 28 || mode == 29) {
  vec2 p=(UV/TEXTURE_PIXEL_SIZE-vec2(48.0))/content_size-vec2(.5);
  if(mode==28){float sector=6.2831853/max(2.0,floor(amount)); float a=atan(p.y,p.x)+effect_angle; a=abs(mod(a,sector)-sector*.5); p=length(p)*vec2(cos(a),sin(a));}
  else{float r=length(p); p+=normalize(p+vec2(.00001))*sin(r*spacing*6.2831853)*amount/content_size;}
  vec2 mapped=((p+vec2(.5))*content_size+vec2(48.0))*TEXTURE_PIXEL_SIZE;
  c=texture(TEXTURE,mapped); c.rgb/=max(c.a,.00001);
 } else if(mode==30){float line=step(.5,fract((UV.y/TEXTURE_PIXEL_SIZE.y-48.0)/max(1.0,spacing))); c.rgb*=1.0-line*amount;
 } else if (mode == 0 && masked) {
  vec2 p = (UV / TEXTURE_PIXEL_SIZE - vec2(48.0)) / content_size;
  c.a *= texture(layer_mask, clamp(p, vec2(0.0), vec2(1.0))).r;
 } else if (mode == 1) { c.rgb = clamp(c.rgb + amount, vec3(0.0), vec3(1.0));
 } else if (mode == 2) { c.rgb = clamp((c.rgb - .5) * amount + .5, vec3(0.0), vec3(1.0));
 } else if (mode == 3) { float l = dot(c.rgb, vec3(.2126,.7152,.0722)); c.rgb = clamp(mix(vec3(l), c.rgb, amount), vec3(0.0), vec3(1.0));
 } else if (mode == 4) {
  vec4 sum=vec4(0.0); float total=0.0; float sigma=max(.001,amount*.4); float stride=max(1.0,amount/16.0);
  for(int i=-16;i<=16;i++){float sample_offset=float(i)*stride; float weight=exp(-.5*sample_offset*sample_offset/(sigma*sigma)); sum+=texture(TEXTURE,UV+blur_direction*TEXTURE_PIXEL_SIZE*sample_offset)*weight; total+=weight;}
  c=sum/max(.00001,total); c.rgb/=max(c.a,.00001);
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
  c=vec4(texture(curve_lut,vec2(c.r,.5)).r,texture(curve_lut,vec2(c.g,.5)).g,texture(curve_lut,vec2(c.b,.5)).b,texture(curve_lut,vec2(c.a,.5)).a);
  vec2 p=UV/TEXTURE_PIXEL_SIZE-vec2(48.0);
  if(any(lessThan(p,vec2(0.0))) || any(greaterThan(p,content_size))) c.a=0.0;
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
 vec4 result = vec4(c.rgb*c.a,c.a);
 if (mode == 24 && effects_selection_only) {
  vec2 p = (UV / TEXTURE_PIXEL_SIZE - vec2(48.0)) / content_size;
  float selected = has_effect_selection && all(greaterThanEqual(p,vec2(0.0))) && all(lessThanEqual(p,vec2(1.0))) ? texture(effect_selection,p).a : 0.0;
  result = mix(texture(effect_original,UV),result,selected);
 }
 COLOR = result;
}
"""

class LayerDrawing extends Node2D:
	signal source_changed
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
					noise.changed.connect(func(): source_changed.emit())
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
var composition_viewport:=SubViewport.new()
var _composition_enabled:=false
var _warp_shader:=Shader.new()
var _export_display := TextureRect.new()
var document: KiwiImageDocument
var views: Dictionary = {}
var _topology := ""
var _live_signatures: Dictionary = {}
var _dirty_layers: Dictionary = {}
var _enabled := true
var _settling_frames := 10
var _shader := Shader.new()
var _straight_shader := Shader.new()
var render_scale := 1.0
var exporting := false
var preview_size:=Vector2i.ZERO
var preview_transform:=Transform2D.IDENTITY
var preview_interactive_limit := 2048
var _preview_zoom := 1.0
var _preview_origin := Vector2.ZERO
var _interactive_preview := false
var _refine_at_usec := 0


func _ready() -> void:
	_shader.code = EFFECT_CODE
	_warp_shader.code=preload("res://Workspaces/ImageWorkspace/image_warp_render.gd").CODE
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
	composition_viewport.transparent_bg=true; composition_viewport.disable_3d=true
	composition_viewport.world_2d=viewport.world_2d
	composition_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(composition_viewport)
	RenderingServer.frame_post_draw.connect(_settle_cached_layers)
	set_process(false)


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
	if preview_size != Vector2i.ZERO and not exporting:
		render_scale = _requested_preview_resolution()
		preview_transform = Transform2D(0, _preview_origin).scaled_local(Vector2.ONE*_preview_zoom/render_scale)
	_live_signatures.clear()
	viewport.size = preview_size if preview_size!=Vector2i.ZERO and not exporting else Vector2i((Vector2(document.canvas_size)*render_scale).round().max(Vector2.ONE))
	viewport.canvas_transform=preview_transform if not exporting else Transform2D.IDENTITY
	export_viewport.size = viewport.size
	composition_viewport.size=Vector2i((Vector2(document.canvas_size)*render_scale).round()).max(Vector2i.ONE)
	_export_display.size = Vector2(viewport.size)
	var topology := ""
	for layer in document.layers:
		topology += layer.id + layer.parent_id + layer.kind + str(layer.properties.get("effects_selection_only",false))+str(layer.warp!=null)
		for region in layer.live_paint: topology += region.id + str(region.is_live())
		for effect in layer.effects: topology += str(effect.get("id", "")) + str(effect.get("type", "")) + str(effect.get("shader", ""))
	if topology != _topology:
		_topology = topology
		for child in get_children():
			if child != viewport and child != export_viewport and child != composition_viewport: remove_child(child); child.queue_free()
		for child in viewport.get_children(): viewport.remove_child(child); child.queue_free()
		views.clear()
		for layer in document.children(): _build_layer(layer, viewport)
	for layer in document.layers:
		if views.has(layer.id): _update_layer(layer, views[layer.id])
	_schedule_cached_layers()


func _effect_stages(layer: KiwiImageLayer) -> Array:
	var result: Array=[]
	if layer.warp!=null: result.append({"type":"warp","enabled":true})
	result.append({"type":"mask","enabled":true})
	for effect in layer.effects:
		result.append(effect)
		if effect.get("type","")=="blur":
			var vertical: Dictionary=effect.duplicate(true); vertical.type="blur_vertical"; result.append(vertical)
		if bool(layer.properties.get("effects_selection_only",false)): result.append({"type":"effects_selection","enabled":true})
	result.append({"type":"values"}); result.append({"type":"perspective"})
	return result


func _build_layer(layer: KiwiImageLayer, parent: Node) -> void:
	var target_size := Vector2i((_content_dimensions(layer)*render_scale).ceil()) + Vector2i.ONE * PAD * 2
	var base := _surface(target_size)
	var live_root := Node2D.new()
	live_root.position = Vector2.ONE * PAD
	base.add_child(live_root)
	var live_views: Dictionary = {}
	for region in layer.live_paint:
		var display := Sprite2D.new()
		display.centered = false
		live_root.add_child(display)
		live_views[region.id] = {"display":display,"signature":0}
	var drawing := LayerDrawing.new()
	drawing.source_changed.connect(invalidate_layer.bind(layer.id))
	drawing.layer = layer
	drawing.position = Vector2.ONE * PAD
	base.add_child(drawing)
	var stages: Array[Dictionary] = []
	var previous := base
	var effects: Array = _effect_stages(layer)
	var original: Texture2D
	for effect: Dictionary in effects:
		if effect.get("type","") not in ["mask","values","perspective","effects_selection","blur_vertical"]: original=previous.get_texture()
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
		elif effect.get("type","")=="warp": material.shader=_warp_shader
		else: material.shader = _shader
		display.material = material
		surface.add_child(display)
		stages.append({"viewport":surface,"display":display,"material":material,"input_viewport":input_surface,"input_display":input_display,"original":original})
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
	views[layer.id] = {"root":root,"output":output,"direct_text":direct_text,"base":base,"drawing":drawing,"stages":stages,"blend":blending,"signature":0,"allocated_dimensions":layer.dimensions,"live_root":live_root,"live_views":live_views}
	# A group is composited before applying its mask, effects and opacity. Drawing
	# each child directly under the output would apply group alpha per child and
	# produce darker/less-transparent overlaps instead of a single group result.
	if layer.kind == "group":
		var content := Node2D.new()
		content.position = Vector2.ONE * PAD
		base.add_child(content)
		for child in document.children(layer.id): _build_layer(child, content)
	else:
		for child in document.children(layer.id): _build_layer(child, root)


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
	var direct: bool=layer.kind=="text" and layer.warp==null and layer.blend==0 and layer.effects.is_empty() and preload("res://Workspaces/ImageWorkspace/image_values.gd").operations(layer).is_empty() and layer.mask==null and not layer.clip_to_below and is_zero_approx(float(layer.properties.get("yaw_up_down",0))) and is_zero_approx(float(layer.properties.get("yaw_left_right",0)))
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
	_update_live_paint(layer, view)
	if layer.properties.get("texture_material") is KiwiTextureMaterial:
		view.drawing.material=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").material(layer.properties.texture_material,layer.dimensions,document.world_transform(layer))
	else: view.drawing.material=null
	view.drawing.scale = raster_scale if stable else Vector2.ONE * (1.0 if layer.kind=="group" else render_scale)
	view.live_root.scale = view.drawing.scale
	if stable:
		view.output.scale=Vector2.ONE*render_scale/raster_scale
		view.output.position=-Vector2.ONE*PAD*view.output.scale
	var signature := hash([layer.dimensions,layer.properties,layer.texture,render_scale])
	if int(view.signature) != signature or layer.kind=="text":
		view.signature = signature
		view.drawing.queue_redraw()
	var effects: Array = _effect_stages(layer)
	var modes := {"mask":0,"brightness":1,"contrast":2,"saturation":3,"blur":4,"outline":5,"shadow":6,"grayscale":7,"invert":8,"glow":9,"wave":10,"curves":11,"perspective":12,
		"sharpen":13,"pixelate":14,"grain":15,"chromatic":16,"halftone":17,"posterize":18,"vignette":19,"gradient_map":20,"color_replace":21,"twirl":22,"mirror":23,"effects_selection":24,"emboss":25,"edge_detect":26,"motion_blur":27,"kaleidoscope":28,"ripple":29,"scanlines":30,"radial_blur":31}
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
			material.set_shader_parameter("selection_local",bool(layer.properties.get("values_selection_local",false)))
			material.set_shader_parameter("selection_origin",mapping.origin)
			material.set_shader_parameter("selection_x",mapping.x/(raster_scale.x if stable else render_scale))
			material.set_shader_parameter("selection_y",mapping.y/(raster_scale.y if stable else render_scale))
			material.set_shader_parameter("document_size",Vector2(document.canvas_size))
			material.set_shader_parameter("content_extent",_content_dimensions(layer)*(raster_scale if stable else Vector2.ONE*render_scale))
		elif effect.get("type","")=="warp" and layer.warp!=null:
			material.set_shader_parameter("deformation",layer.warp.texture())
			material.set_shader_parameter("field_size",Vector2(layer.warp.grid_size))
			material.set_shader_parameter("enabled",layer.warp.enabled)
			material.set_shader_parameter("content_size",_content_dimensions(layer)*(raster_scale if stable else Vector2.ONE*render_scale))
		elif effect.get("type","") == "shader":
			stage.display.material = material if enabled else null
			for key in effect.get("uniforms",{}): material.set_shader_parameter(key,effect.uniforms[key])
		else:
			material.set_shader_parameter("mode",4 if enabled and effect.get("type","")=="blur_vertical" else (int(modes.get(effect.get("type",""),0)) if enabled else 0))
			material.set_shader_parameter("blur_direction",Vector2.DOWN if effect.get("type","")=="blur_vertical" else Vector2.RIGHT)
			material.set_shader_parameter("mirror_side",int(effect.get("mirror_side",0)))
			material.set_shader_parameter("preserve_color",bool(effect.get("preserve_color",false)))
			material.set_shader_parameter("mirror_position",float(effect.get("mirror_position",0.5)))
			material.set_shader_parameter("effect_angle",deg_to_rad(float(effect.get("angle",0.0))))
			material.set_shader_parameter("spacing",float(effect.get("spacing",12.0)))
			material.set_shader_parameter("effects_selection_only",bool(layer.properties.get("effects_selection_only",false)))
			material.set_shader_parameter("has_effect_selection",layer.properties.get("effects_selection")!=null)
			material.set_shader_parameter("effect_selection",layer.properties.get("effects_selection"))
			if effect.get("type","")=="effects_selection": material.set_shader_parameter("effect_original",stage.original)
			material.set_shader_parameter("masked",effect.get("type","")=="mask" and layer.mask != null)
			material.set_shader_parameter("layer_mask",layer.mask)
			material.set_shader_parameter("content_size",layer.dimensions*(raster_scale if stable else Vector2.ONE*render_scale))
			material.set_shader_parameter("yaw",Vector2(deg_to_rad(float(layer.properties.get("yaw_up_down",0))),deg_to_rad(float(layer.properties.get("yaw_left_right",0)))))
			material.set_shader_parameter("amount",float(effect.get("amount",1.0))*(render_scale if effect.get("type","") in ["blur","blur_vertical","outline","shadow","glow","wave","chromatic","pixelate","halftone"] else 1.0))
			material.set_shader_parameter("tint",effect.get("color",Color(0,0,0,.7)))
			material.set_shader_parameter("tint2",effect.get("color2",Color.WHITE))
			material.set_shader_parameter("offset",effect.get("offset",Vector2(8,8))*render_scale)
			if effect.get("curve") is Curve:
				var lut:=Image.create(256,1,false,Image.FORMAT_RGBAF)
				var channels: Dictionary=effect.get("curves",{})
				for sample in 256:
					var input:=float(sample)/255; var master: float=effect.curve.sample_baked(input)
					var color:=Color(master,master,master,input)
					for channel in 4:
						var curve: Curve=channels.get(["red","green","blue","alpha"][channel])
						if curve!=null: color[channel]=curve.sample_baked(master if channel<3 else input)
					lut.set_pixel(sample,0,color)
				if not stage.has("curve_texture"): stage.curve_texture=ImageTexture.create_from_image(lut)
				else: stage.curve_texture.update(lut)
				material.set_shader_parameter("curve_lut",stage.curve_texture)
			material.set_shader_parameter("clipped",effect.get("type","")=="mask" and layer.clip_to_below)
			if effect.get("type","")=="mask" and layer.clip_to_below:
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


func invalidate_layer(layer_id: String) -> void:
	# ImageTexture.update() may retain its identity during a brush gesture. The
	# painter calls this explicitly; Resource.changed also covers other producers.
	if document == null or not views.has(layer_id): return
	_dirty_layers[layer_id] = true
	var affected: Dictionary = {layer_id:true}
	_propagate_render_dependencies(affected)
	for id in affected:
		if not views.has(id): continue
		var view: Dictionary = views[id]
		view.frames_left = _settling_frames
		if _enabled: _set_layer_update_mode(view, SubViewport.UPDATE_ALWAYS)


func _watch_source(resource: Resource, layer_id: String) -> void:
	if resource == null: return
	var callback := invalidate_layer.bind(layer_id)
	if not resource.changed.is_connected(callback): resource.changed.connect(callback)


func _source_stamp(value: Variant, layer_id: String) -> Variant:
	if value is Dictionary:
		var parts: Array = []
		for key in value: parts.append(key); parts.append(_source_stamp(value[key], layer_id))
		return hash(parts)
	if value is Array:
		var parts: Array = []
		for item in value: parts.append(_source_stamp(item, layer_id))
		return hash(parts)
	if value is Resource:
		_watch_source(value, layer_id)
		if value is Shader: return hash(value.code)
		if value is ActorObjectData: return _source_stamp(value.values, layer_id)
		if value is KiwiTextureMaterial:
			_watch_source(value.image, layer_id); _watch_source(value.mix_mask, layer_id)
			if value.secondary != null: _source_stamp(value.secondary, layer_id)
			return _live_material_signature(value)
		if value is Curve:
			var points: Array = [value.min_value, value.max_value]
			for index in value.point_count:
				points.append([value.get_point_position(index), value.get_point_left_tangent(index), value.get_point_right_tangent(index), value.get_point_left_mode(index), value.get_point_right_mode(index)])
			return hash(points)
	return value


func _layer_source_stamp(layer: KiwiImageLayer) -> int:
	var parts: Array = [layer.kind, layer.dimensions, layer.position, layer.rotation,
		layer.opacity, layer.blend, layer.visible, layer.isolated, layer.clip_to_below,
		document.isolation_allows(layer), document.world_transform(layer), render_scale,
		_source_stamp(layer.texture, layer.id), _source_stamp(layer.mask, layer.id),
		_source_stamp(layer.properties, layer.id), _source_stamp(layer.effects, layer.id)]
	if layer.warp != null: parts.append([layer.warp, layer.warp.enabled, layer.warp.revision])
	for region in layer.live_paint:
		parts.append([region.id, region.template_id, region.mapping, region.opacity, region.coordinate_rect,
			_source_stamp(region.coverage, layer.id), _source_stamp(region.coordinates, layer.id), _source_stamp(region.raster, layer.id)])
		var template := document.live_material_for_id(region.template_id)
		if template != null:
			parts.append([template.visible, _source_stamp(template.material, layer.id)])
	return hash(parts)


func _animated_source(value: Variant) -> bool:
	if value is KiwiTextureMaterial:
		return _animated_source(value.image) or _animated_source(value.mix_mask) or _animated_source(value.secondary)
	if value is AtlasTexture: return _animated_source(value.atlas)
	if value is Texture2D:
		return value is ViewportTexture or value.get_class() in ["AnimatedTexture", "CameraTexture", "ExternalTexture"]
	if value is Dictionary:
		for item in value.values():
			if _animated_source(item): return true
	if value is Array:
		for item in value:
			if _animated_source(item): return true
	return false


func _layer_needs_time(layer: KiwiImageLayer) -> bool:
	if _animated_source(layer.texture) or _animated_source(layer.mask) or _animated_source(layer.properties): return true
	for effect in layer.effects:
		if not bool(effect.get("enabled", true)): continue
		if _animated_source(effect.get("uniforms", {})): return true
		if effect.get("shader") is Shader:
			var code: String = effect.shader.code
			# Includes may contain TIME or animated resources, so remain conservative.
			if code.contains("TIME") or code.contains("#include") or code.contains("global uniform"): return true
	for region in layer.live_paint:
		if _animated_source(region.coverage) or _animated_source(region.raster) or _animated_source(region.coordinates): return true
		var template := document.live_material_for_id(region.template_id)
		if template != null and _animated_source(template.material): return true
	return false


func _propagate_render_dependencies(affected: Dictionary) -> void:
	# Sources feed ancestor groups and clip-to-below siblings. Repeat because a
	# clipped sibling can feed another clipped sibling or a containing group.
	var changed := true
	while changed:
		changed = false
		for layer in document.layers:
			if not affected.has(layer.id): continue
			var parent := document.layer_for_id(layer.parent_id)
			var seen: Dictionary = {}
			while parent != null and not seen.has(parent.id):
				seen[parent.id] = true
				if parent.kind == "group" and not affected.has(parent.id):
					affected[parent.id] = true; changed = true
				parent = document.layer_for_id(parent.parent_id)
			var siblings := document.children(layer.parent_id)
			var next := siblings.find(layer) + 1
			if next > 0 and next < siblings.size() and siblings[next].clip_to_below and not affected.has(siblings[next].id):
				affected[siblings[next].id] = true; changed = true


func _schedule_cached_layers() -> void:
	var dynamic: Dictionary = {}
	_settling_frames = 8
	var dependency_frames: Dictionary = {}
	for layer in document.layers:
		if not views.has(layer.id): continue
		var view: Dictionary = views[layer.id]
		var signature := _layer_source_stamp(layer)
		if int(view.get("cache_signature", -1)) != signature:
			view.cache_signature = signature; _dirty_layers[layer.id] = true
		if _layer_needs_time(layer): dynamic[layer.id] = true
		_settling_frames = maxi(_settling_frames, _render_dependency_frames(layer, dependency_frames, {}) + 3)
	_propagate_render_dependencies(_dirty_layers)
	_propagate_render_dependencies(dynamic)
	for id in views:
		var view: Dictionary = views[id]
		view.dynamic = dynamic.has(id)
		if _dirty_layers.has(id): view.frames_left = _settling_frames
		var render: bool = _enabled and (exporting or bool(view.dynamic) or int(view.get("frames_left", 0)) > 0)
		_set_layer_update_mode(view, SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED)
	_dirty_layers.clear()


func _render_dependency_frames(layer: KiwiImageLayer, memo: Dictionary, seen: Dictionary) -> int:
	if memo.has(layer.id): return int(memo[layer.id])
	if seen.has(layer.id) or not views.has(layer.id): return 0
	seen = seen.duplicate(); seen[layer.id] = true
	var view: Dictionary = views[layer.id]
	var passes: int = view.stages.size() + 1
	for stage in view.stages:
		if stage.input_viewport != null: passes += 1
	var dependency := 0
	if layer.kind == "group":
		for child in document.children(layer.id):
			dependency = maxi(dependency, _render_dependency_frames(child, memo, seen))
	if layer.clip_to_below:
		var siblings := document.children(layer.parent_id)
		var previous := siblings.find(layer) - 1
		if previous >= 0: dependency = maxi(dependency, _render_dependency_frames(siblings[previous], memo, seen))
	memo[layer.id] = passes + dependency
	return passes + dependency


func _set_layer_update_mode(view: Dictionary, mode: int) -> void:
	view.base.render_target_update_mode = mode
	for stage in view.stages:
		stage.viewport.render_target_update_mode = mode
		if stage.input_viewport != null: stage.input_viewport.render_target_update_mode = mode


func _settle_cached_layers() -> void:
	if not _enabled: return
	for view in views.values():
		if view.base.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			view.frames_rendered = int(view.get("frames_rendered", 0)) + 1
		if exporting: continue
		if bool(view.get("dynamic", false)): continue
		var frames := int(view.get("frames_left", 0))
		if frames <= 0: continue
		view.frames_left = frames - 1
		if frames == 1: _set_layer_update_mode(view, SubViewport.UPDATE_DISABLED)


func sync_transforms(value: KiwiImageDocument) -> void:
	document=value
	_live_signatures.clear()
	for layer in document.layers:
		if not views.has(layer.id): continue
		var view: Dictionary=views[layer.id]
		if layer.kind=="text":
			view.stable_text_surface=true
			_update_layer(layer,view)
			continue
		if layer.kind == "group":
			# Group resize already resizes its children in the document. Resize the
			# containing source without scaling its composed output a second time.
			_update_layer(layer, view)
			continue
		var transform:=layer.local_transform(); transform.origin*=render_scale; view.root.transform=transform
		var allocated: Vector2=view.get("allocated_dimensions",layer.dimensions)
		var preview_scale:=layer.dimensions/allocated.max(Vector2.ONE)
		view.output.scale=preview_scale
		view.output.position=-Vector2.ONE*PAD*preview_scale
		view.output.modulate=Color(layer.opacity,layer.opacity,layer.opacity,layer.opacity) if layer.blend==0 else Color(1,1,1,layer.opacity)
	_schedule_cached_layers()


func texture() -> Texture2D:
	return viewport.get_texture()

func composition_texture() -> Texture2D: return composition_viewport.get_texture()

func set_composition_preview_enabled(enabled: bool) -> void:
	_composition_enabled=enabled
	composition_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED


func _content_dimensions(layer: KiwiImageLayer) -> Vector2:
	return layer.content_dimensions()


func _update_live_paint(layer: KiwiImageLayer, view: Dictionary) -> void:
	for region in layer.live_paint:
		var region_view: Dictionary = view.live_views.get(region.id, {})
		if region_view.is_empty(): continue
		var display: Sprite2D = region_view.display
		display.modulate = Color(1, 1, 1, region.opacity)
		if not region.is_live():
			display.texture = region.raster
			display.material = null
			display.visible = region.raster != null
		else:
			var template := document.live_material_for_id(region.template_id)
			display.visible = template != null and template.visible and template.material != null and region.coverage != null
			if not display.visible: continue
			display.texture = region.coverage
			# Template mutations replace the independent instance; an unchanged
			# template reuses the compiled shader and its material across frames.
			if not _live_signatures.has(template.id): _live_signatures[template.id] = _live_material_signature(template.material)
			var signature := hash([_live_signatures[template.id], region.coverage, region.coordinates, region.coordinate_rect, region.mapping, region.opacity, layer.dimensions])
			if int(region_view.signature) != signature:
				region_view.signature = signature
				var material := template.material.copy_material()
				material.coverage = region.coverage
				if material.alignment == "stroke": material.alignment = "canvas"
				display.material = preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").material(material, layer.dimensions, region.mapping)
				(display.material as ShaderMaterial).set_shader_parameter("coverage_opacity", region.opacity)
				(display.material as ShaderMaterial).set_shader_parameter("has_coordinate_map", region.coordinates != null)
				(display.material as ShaderMaterial).set_shader_parameter("coordinate_map", region.coordinates)
				(display.material as ShaderMaterial).set_shader_parameter("coordinate_rect", Vector4(region.coordinate_rect.position.x, region.coordinate_rect.position.y, region.coordinate_rect.size.x, region.coordinate_rect.size.y))
			display.modulate = Color.WHITE
		if display.texture != null:
			display.scale = layer.dimensions / display.texture.get_size().max(Vector2.ONE)


func _live_material_signature(material: KiwiTextureMaterial) -> int:
	# Also tolerate scripts/inspectors editing an instance in place. The active UI
	# usually replaces it for undo, but a Resource identity alone misses such edits.
	return hash([material.material_id, material.parameters, material.image,
		material.texture_size, material.rotation, material.alignment,
		material.mapping_origin, material.tint_strength, material.tiling,
		material.blending, material.mix_amount, material.mix_distribution,
		material.mix_mask, material.relief, material.relief_softness,
		material.light_direction, material.highlight, material.shadow,
		_live_material_signature(material.secondary) if material.secondary != null else 0])


func source_image(layer: KiwiImageLayer) -> Image:
	# Bucket detection needs the entire ordered source, not the transparent top
	# raster left available for subsequent Color strokes. Effects remain external.
	if document == null or layer == null: return null
	if layer.live_paint.is_empty():
		return layer.texture.get_image() if layer.texture != null else null
	if not is_equal_approx(render_scale, 1.0):
		# Bucket tolerance must inspect native pixels, not a resampled screen
		# preview. Isolate this source so other large layers need no full-size pass.
		var native_document := KiwiImageDocument.new()
		native_document.canvas_size = Vector2i(layer.dimensions.ceil())
		native_document.live_materials = document.live_materials
		var native_layer := layer.copy_layer()
		native_layer.parent_id = ""
		var source_frame := document.world_transform(layer)
		var half := layer.dimensions*.5
		native_layer.position = source_frame.origin-half+source_frame.basis_xform(half)
		native_layer.rotation = 0.0
		native_layer.properties.basis_x = source_frame.x
		native_layer.properties.basis_y = source_frame.y
		native_layer.properties.flip_x = false
		native_layer.properties.flip_y = false
		native_layer.effects.clear()
		native_layer.mask = null
		native_layer.clip_to_below = false
		native_document.layers.append(native_layer)
		var native_renderer := KiwiImageRenderer.new()
		get_tree().root.add_child(native_renderer)
		native_renderer.sync(native_document)
		var native_pixels: Image = await native_renderer.source_image(native_layer)
		native_renderer.queue_free()
		return native_pixels
	var source_document := document
	sync(document)
	if not views.has(layer.id): return null
	for frame in 3: await RenderingServer.frame_post_draw
	if document != source_document or not views.has(layer.id) or document.layer_for_id(layer.id) != layer: return null
	var base: SubViewport = views[layer.id].base
	var pixels := base.get_texture().get_image()
	if pixels == null or pixels.is_empty(): return null
	pixels = pixels.get_region(Rect2i(Vector2i.ONE * PAD, base.size - Vector2i.ONE * PAD * 2))
	var native_size := Vector2i(layer.texture.get_size()) if layer.texture != null else Vector2i(layer.dimensions.ceil())
	if pixels.get_size() != native_size:
		pixels.resize(native_size.x, native_size.y, Image.INTERPOLATE_BILINEAR)
	pixels.convert(Image.FORMAT_RGBA8)
	var bytes := pixels.get_data()
	for index in range(0, bytes.size(), 4):
		var alpha := int(bytes[index + 3])
		if alpha == 0: continue
		for channel in 3: bytes[index + channel] = clampi(roundi(float(bytes[index + channel]) * 255.0 / alpha), 0, 255)
	pixels.set_data(native_size.x, native_size.y, false, Image.FORMAT_RGBA8, bytes)
	return pixels


func bake_live_material(template_id: String) -> bool:
	# Render all replacements before mutating the document. A failed GPU readback
	# leaves every live region intact and the caller's undo transaction can cancel.
	if document == null: return false
	var target_document := document
	var template := target_document.live_material_for_id(template_id)
	if template == null or template.material == null: return false
	# Visibility belongs to the live template, not to the containing raster layer.
	# Refuse to silently discard hidden coverage while converting ownership.
	if not template.visible: return false
	var expected_material := _live_material_signature(template.material)
	var replacements: Array[Dictionary] = []
	for layer in target_document.layers:
		for region in layer.live_paint:
			if region.template_id != template_id or region.coverage == null: continue
			var material := template.material.copy_material()
			material.coverage = region.coverage
			if material.alignment == "stroke": material.alignment = "canvas"
			var pixels: Image = await preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").preview(self, material, Vector2i(region.coverage.get_size()), layer.dimensions, region.mapping, region.coordinates, region.coordinate_rect)
			if pixels == null or pixels.is_empty() or document != target_document: return false
			# A GPU compilation/allocation failure can yield a valid but blank image.
			# Do not discard nonempty, visibly colored coverage in that case.
			if material.image == null and not pixels.get_used_rect().has_area():
				var primary: Color = material.parameters.get("primary", Color.WHITE)
				var secondary: Color = material.parameters.get("secondary", Color.WHITE)
				var mask_image := region.coverage.get_image()
				if maxf(primary.a, secondary.a) > 0.0 and mask_image != null and mask_image.get_used_rect().has_area(): return false
			replacements.append({"layer":layer,"region":region,"texture":ImageTexture.create_from_image(pixels)})
	# Async rendering can span UI events. Never bake stale settings or resurrect a
	# region deleted while the GPU was working, even when the document is the same.
	if target_document.live_material_for_id(template_id) != template or _live_material_signature(template.material) != expected_material: return false
	for replacement in replacements:
		if not target_document.layers.has(replacement.layer) or not replacement.layer.live_paint.has(replacement.region): return false
	for replacement in replacements:
		var region: KiwiLivePaintRegion = replacement.region
		region.raster = replacement.texture
		region.coverage = null
		region.coordinates = null
		region.template_id = ""
	# There are no linked regions left, so removal cannot delete the baked pixels.
	target_document.delete_live_material(template_id)
	for layer in target_document.layers: _collapse_baked_paint(layer)
	sync(target_document)
	return true


func _collapse_baked_paint(layer: KiwiImageLayer) -> void:
	# Once a layer contains only raster segments, restore a normal editable bitmap.
	# With another live template present, retain segment order around its coverage.
	if layer.live_paint.is_empty(): return
	for region in layer.live_paint:
		if region.is_live(): return
	var size := Vector2i(layer.texture.get_size()) if layer.texture != null else Vector2i(layer.dimensions.ceil())
	var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0, 0, 0, 0))
	for region in layer.live_paint:
		if region.raster == null: continue
		var source := region.raster.get_image()
		if source == null: continue
		source = source.duplicate()
		if source.get_size() != size: source.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		source.convert(Image.FORMAT_RGBA8)
		if not is_equal_approx(region.opacity, 1.0):
			var data := source.get_data()
			for index in range(3, data.size(), 4): data[index] = roundi(float(data[index]) * region.opacity)
			source.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
		pixels.blend_rect(source, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	if layer.texture != null:
		var top := layer.texture.get_image()
		if top != null: pixels.blend_rect(top, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	layer.texture = ImageTexture.create_from_image(pixels)
	layer.paint_base = layer.texture
	layer.live_paint.clear()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	export_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED
	for view in views.values():
		var render: bool = enabled and (exporting or bool(view.get("dynamic", false)) or int(view.get("frames_left", 0)) > 0)
		_set_layer_update_mode(view, SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED)
	composition_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if enabled and _composition_enabled else SubViewport.UPDATE_DISABLED


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
		var passes:=4+(2 if layer.warp!=null else 0)
		var current: KiwiImageLayer=layer
		while current!=null:
			passes+=4+current.effects.size()*(2 if bool(current.properties.get("effects_selection_only",false)) else 1)
			for effect in current.effects:
				if effect.get("type","")=="shader": passes+=1
				if effect.get("type","")=="blur": passes+=1
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
	_apply_preview_resolution()


func set_interactive_preview(active: bool) -> void:
	if _interactive_preview == active: return
	_interactive_preview = active
	if active:
		_refine_at_usec = 0
		set_process(false)
		_apply_preview_resolution()
	else:
		# Keep the economical resolution through rapid slider edits, then refine
		# only when the user pauses. Native coverage/resources are never resized.
		_refine_at_usec = Time.get_ticks_usec() + 350000
		set_process(true)


func _process(_delta: float) -> void:
	if _refine_at_usec == 0 or _interactive_preview: set_process(false); return
	if exporting or Time.get_ticks_usec() < _refine_at_usec: return
	_refine_at_usec = 0
	set_process(false)
	_apply_preview_resolution()


func _apply_preview_resolution() -> void:
	if exporting or document == null or preview_size == Vector2i.ZERO: return
	var desired := _requested_preview_resolution()
	if is_equal_approx(desired, render_scale): return
	render_scale = desired
	preview_transform = Transform2D(0, _preview_origin).scaled_local(Vector2.ONE*_preview_zoom/render_scale)
	sync(document)


func _requested_preview_resolution() -> float:
	# Power-of-two tiers avoid reallocating render targets at every wheel tick.
	var desired := clampf(pow(2.0, ceil(log(maxf(.0625, _preview_zoom))/log(2.0))), .0625, 1.0)
	if _interactive_preview or _refine_at_usec != 0:
		var extent := maxf(document.canvas_size.x, document.canvas_size.y)
		for layer in document.layers:
			var size := _content_dimensions(layer)
			extent = maxf(extent, maxf(size.x, size.y))
		desired = minf(desired, float(preview_interactive_limit)/maxf(1.0, extent))
	return desired


func set_preview_camera(dimensions: Vector2, origin: Vector2, zoom: float) -> void:
	if exporting: return
	if preview_size == Vector2i.ZERO or not is_equal_approx(_preview_zoom, zoom):
		_refine_at_usec = Time.get_ticks_usec() + 350000
		set_process(true)
	preview_size=Vector2i(dimensions.ceil()).max(Vector2i.ONE)
	_preview_zoom = maxf(.001, zoom)
	_preview_origin = origin
	preview_transform=Transform2D(0,origin).scaled_local(Vector2.ONE*_preview_zoom/render_scale)
	viewport.size=preview_size
	viewport.canvas_transform=preview_transform
	set_preview_scale(zoom)
