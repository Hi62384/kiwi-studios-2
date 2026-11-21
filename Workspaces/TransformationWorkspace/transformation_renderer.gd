class_name KiwiTransformationRenderer
extends Node
const CODE := """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D image_a : filter_linear;
uniform sampler2D image_b : filter_linear;
uniform float progress=0.0;
uniform float morph=0.0;
uniform vec2 dimensions=vec2(1280.0,720.0);
uniform float opacity=1.0;
uniform int growth=0;
uniform bool reveal_replace=false;
uniform vec2 origin=vec2(.5);
uniform int path_count=0;
uniform vec2 path_points[64];
uniform float path_width=.3;
uniform sampler2D field_a : filter_linear, repeat_disable;
uniform sampler2D field_b : filter_linear, repeat_disable;
uniform bool has_fields=false;
uniform bool implicit_shape=false;
uniform bool feature_appearance=true;
uniform float topology_bias=0.0;
uniform int reveal_kind=0;
uniform vec2 direction=vec2(0.0,1.0);
uniform float growth_radius=.8;
uniform int mask_count=0;
uniform sampler2D transfer_mask0;
uniform sampler2D transfer_mask1;
uniform sampler2D transfer_mask2;
uniform sampler2D transfer_mask3;
varying vec2 target_uv;
vec4 premul_fetch(sampler2D source,ivec2 p){ivec2 n=textureSize(source,0);vec4 c=texelFetch(source,clamp(p,ivec2(0),n-1),0);return vec4(c.rgb*c.a,c.a);}
vec4 sample_pm(sampler2D source,vec2 uv){
 if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0))))return vec4(0.0);
 vec2 p=uv*vec2(textureSize(source,0))-.5;ivec2 cell=ivec2(floor(p));vec2 f=fract(p);
 return mix(mix(premul_fetch(source,cell),premul_fetch(source,cell+ivec2(1,0)),f.x),mix(premul_fetch(source,cell+ivec2(0,1)),premul_fetch(source,cell+ivec2(1,1)),f.x),f.y);
}
void vertex(){
 target_uv=COLOR.rg+COLOR.ba/255.0;
 VERTEX=mix(UV,target_uv,morph)*dimensions;
}
void fragment(){
 vec4 a=sample_pm(image_a,UV); vec4 b=sample_pm(image_b,target_uv);
 vec4 fa=has_fields?texture(field_a,UV):vec4(0.0);vec4 fb=has_fields?texture(field_b,target_uv):vec4(0.0);
 float appearance=progress;
 if(feature_appearance && has_fields && growth==0){
  float novel_b=smoothstep(.08+distance(target_uv,origin)*.2,.45+distance(target_uv,origin)*.2,progress);
  float novel_a=1.0-smoothstep(.15,.75,1.0-progress);
  appearance=mix(appearance,novel_b,fb.a);appearance=mix(appearance,novel_a,fa.a*(1.0-fb.a));
 }
 vec4 c=mix(a,b,appearance);
 if(implicit_shape && has_fields){
  float d=mix(fa.r,fb.r,progress)+topology_bias*sin(progress*3.14159265);
  float edge=max(.0008,fwidth(d));float coverage=smoothstep(-edge,edge,d);
  vec4 near_a=sample_pm(image_a,fa.gb);vec4 near_b=sample_pm(image_b,fb.gb);
  vec3 color=mix(near_a.rgb/max(.00001,near_a.a),near_b.rgb/max(.00001,near_b.a),appearance);
  float alpha=coverage*mix(near_a.a,near_b.a,progress);
  vec4 shaped=vec4(color*alpha,alpha);float interior=smoothstep(0.0,.025,progress)*smoothstep(0.0,.025,1.0-progress);
  c=mix(c,shaped,interior);
 }
 if(growth!=0){
  float g=growth==1?progress:1.0-progress;
  vec2 uv=growth==1?target_uv:UV;
  vec4 source=growth==1?b:a;
  float reach=growth_radius;
  float coverage=1.0-smoothstep(g*reach-.012,g*reach+.012,distance(uv,origin));
  if(reveal_kind==1 && path_count>1){
   float total=0.0; for(int i=1;i<64;i++){if(i>=path_count)break;total+=distance(path_points[i-1],path_points[i]);}
   float passed=0.0; float nearest=1000.0; float along=0.0;
   for(int i=1;i<64;i++){if(i>=path_count)break;vec2 p=path_points[i-1];vec2 d=path_points[i]-p;float len=length(d);float t=clamp(dot(uv-p,d)/max(.000001,dot(d,d)),0.0,1.0);float dist=distance(uv,p+d*t);if(dist<nearest){nearest=dist;along=(passed+t*len)/max(.000001,total);}passed+=len;}
   float travel=along*.82+nearest/max(.01,path_width)*.18;
   coverage=1.0-smoothstep(g-.012,g+.012,travel);
  }
  if(reveal_kind==2){float low=min(0.0,direction.x)+min(0.0,direction.y);float span=abs(direction.x)+abs(direction.y);float travel=(dot(uv,direction)-low)/max(.0001,span);coverage=1.0-smoothstep(g-.01,g+.01,travel);}
  if(reveal_kind==3){vec2 q=origin+(uv-origin)/max(.00001,g);source=growth==1?sample_pm(image_b,q):sample_pm(image_a,q);coverage=g>0.0?1.0:0.0;}
  coverage=g<=0.0?0.0:(g>=1.0?1.0:coverage);
  c=reveal_replace?mix(a,b,coverage):source*coverage;
 }
 if(progress<=0.0)c=a;if(progress>=1.0)c=b;
 float alpha=c.a*opacity;float removed=0.0;
 if(mask_count>0)removed=max(removed,mix(texture(transfer_mask0,UV).a,texture(transfer_mask0,target_uv).a,progress));
 if(mask_count>1)removed=max(removed,mix(texture(transfer_mask1,UV).a,texture(transfer_mask1,target_uv).a,progress));
 if(mask_count>2)removed=max(removed,mix(texture(transfer_mask2,UV).a,texture(transfer_mask2,target_uv).a,progress));
 if(mask_count>3)removed=max(removed,mix(texture(transfer_mask3,UV).a,texture(transfer_mask3,target_uv).a,progress));
 alpha=alpha*(1.0-removed)/max(.00001,1.0-alpha*removed);
 COLOR=vec4(c.rgb/max(c.a,.00001),alpha);
}"""
var viewport := SubViewport.new()
var cache := KiwiTransformationMorphCache.new()
var shader := Shader.new()
var views: Dictionary={}
var status := ""
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_renderer")
func _ready() -> void:
	_native().call("ready", self, CODE)
func texture() -> Texture2D: return viewport.get_texture()
func clear_views() -> void:
	_native().call("clear_views", self)
static func transform_at(a: KiwiTransformationState, b: KiwiTransformationState, t: float, turns: int=0) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_renderer").call("transform_at", a, b, t, turns)
func mesh_for(mapping: Dictionary, extent: Vector2) -> ArrayMesh:
	return _native().call("mesh_for", mapping, extent)
func sync(session: KiwiTransformationSession, time: float, samples: Dictionary = {}) -> void:
	_native().call("sync", self, session, time, samples)
func flattened() -> Image:
	var job: Object = _native().call("flatten", self)
	if not job.finished: await job.completed
	return job.result
