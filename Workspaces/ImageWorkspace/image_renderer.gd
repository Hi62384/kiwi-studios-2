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
        Engine.get_singleton("KiwiNativeServices").service("image_layer_drawing").draw(self)

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
 _native().ready(self)

func _surface(dimensions: Vector2i) -> SubViewport:
 return _native().surface(self,dimensions)

func sync(value: KiwiImageDocument) -> void:
 _native().sync(self,value)

func _effect_stages(layer: KiwiImageLayer) -> Array:
 return _native().effect_stages(layer)

func _build_layer(layer: KiwiImageLayer, parent: Node) -> void:
 _native().build_layer(self,layer,parent)

func _update_layer(layer: KiwiImageLayer, view: Dictionary) -> void:
 _native().update_layer(self,layer,view)

func invalidate_layer(layer_id: String) -> void:
 _native().invalidate_layer(self,layer_id)

func _watch_source(resource: Resource, layer_id: String) -> void:
    if resource == null: return
    var callback := invalidate_layer.bind(layer_id)
    if not resource.changed.is_connected(callback): resource.changed.connect(callback)


func _source_stamp(value: Variant, layer_id: String) -> Variant:
 return _native().source_stamp(self,value,layer_id)

func _layer_source_stamp(layer: KiwiImageLayer) -> int:
 return _native().layer_source_stamp(self,layer)

func _animated_source(value: Variant) -> bool:
 return _native().animated_source(value)

func _layer_needs_time(layer: KiwiImageLayer) -> bool:
 return _native().layer_needs_time(self,layer)

func _propagate_render_dependencies(affected: Dictionary) -> void:
 _native().propagate_render_dependencies(self,affected)

func _schedule_cached_layers() -> void:
 _native().schedule_cached_layers(self)

func _render_dependency_frames(layer: KiwiImageLayer, memo: Dictionary, seen: Dictionary) -> int:
 return _native().render_dependency_frames(self,layer,memo,seen)

func _set_layer_update_mode(view: Dictionary, mode: int) -> void:
 _native().set_layer_update_mode(view,mode)

func _settle_cached_layers() -> void:
 _native().settle_cached_layers(self)

func sync_transforms(value: KiwiImageDocument) -> void:
 _native().sync_transforms(self,value)

func texture() -> Texture2D:
 return _native().texture(self)

func composition_texture() -> Texture2D:
 return _native().composition_texture(self)

func set_composition_preview_enabled(enabled: bool) -> void:
 _native().set_composition_preview_enabled(self,enabled)

func _content_dimensions(layer: KiwiImageLayer) -> Vector2:
 return _native().content_dimensions(layer)

func _update_live_paint(layer: KiwiImageLayer, view: Dictionary) -> void:
 _native().update_live_paint(self,layer,view)

func _live_material_signature(material: KiwiTextureMaterial) -> int:
 return _native().live_material_signature(material)

func source_image(layer: KiwiImageLayer) -> Image:
 var request: Dictionary=_native().prepare_source_image(self,layer)
 if request.is_empty(): return null
 if request.kind=="image": return request.image
 if request.kind=="nested":
  var pixels: Image=await request.renderer.source_image(request.layer)
  request.renderer.queue_free()
  return pixels
 for frame in 3: await RenderingServer.frame_post_draw
 return _native().complete_source_image(self,request)

func bake_live_material(template_id: String) -> bool:
 var request: Dictionary=_native().prepare_bake(self,template_id)
 if request.is_empty(): return false
 for job: Dictionary in request.jobs:
  var pixels: Image=await preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").preview(self,job.material,job.size,job.extent,job.mapping,job.coordinates,job.rect)
  if not _native().accept_bake(self,request,job,pixels): return false
 return _native().complete_bake(self,request)

func _collapse_baked_paint(layer: KiwiImageLayer) -> void:
 _native().collapse_baked_paint(layer)

func set_enabled(enabled: bool) -> void:
 _native().set_enabled(self,enabled)

func flattened() -> Image:
 var request: Dictionary=_native().prepare_flattened(self)
 for frame in request.frames: await RenderingServer.frame_post_draw
 return _native().complete_flattened(self,request)

func set_preview_scale(requested: float) -> void:
 _native().set_preview_scale(self,requested)

func set_interactive_preview(active: bool) -> void:
 _native().set_interactive_preview(self,active)

func _process(_delta: float) -> void:
 _native().process(self)

func _apply_preview_resolution() -> void:
 _native().apply_preview_resolution(self)

func _requested_preview_resolution() -> float:
 return _native().requested_preview_resolution(self)

func set_preview_camera(dimensions: Vector2, origin: Vector2, zoom: float) -> void:
 _native().set_preview_camera(self,dimensions,origin,zoom)

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_renderer")

func _connect_frame() -> void:
 RenderingServer.frame_post_draw.connect(_settle_cached_layers)

func _new_drawing(layer: KiwiImageLayer,source: bool=true) -> Node2D:
 var result:=LayerDrawing.new()
 if source:
  result.source_changed.connect(invalidate_layer.bind(layer.id))
  result.layer=layer
 return result
