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
func _ready() -> void:
	shader.code=CODE; viewport.disable_3d=true; viewport.world_2d=World2D.new(); viewport.transparent_bg=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(viewport); add_child(cache)
func texture() -> Texture2D: return viewport.get_texture()
func clear_views() -> void:
	for view in views.values(): view.node.free()
	views.clear(); cache.requests.clear(); status=""
static func transform_at(a: KiwiTransformationState, b: KiwiTransformationState, t: float, turns: int=0) -> Dictionary:
	var dimensions := a.artwork.dimensions.lerp(b.artwork.dimensions,t); var pivot := a.pivot.lerp(b.pivot,t)
	var rotation := a.artwork.rotation+ (wrapf(b.artwork.rotation-a.artwork.rotation,-PI,PI)+turns*TAU)*t
	var anchor := a.anchor().lerp(b.anchor(),t)
	# Shared canvas group scaling can retain an affine residual (skew / flip).
	# Keep that residual so a state renders exactly as it did while editing,
	# while explicit rotation still takes the shortest angular path.
	var frame_a := a.artwork.local_transform(); var frame_b := b.artwork.local_transform()
	var residual_a := Transform2D(a.artwork.rotation,Vector2.ZERO).affine_inverse()*Transform2D(frame_a.x,frame_a.y,Vector2.ZERO)
	var residual_b := Transform2D(b.artwork.rotation,Vector2.ZERO).affine_inverse()*Transform2D(frame_b.x,frame_b.y,Vector2.ZERO)
	var basis := Transform2D(rotation,Vector2.ZERO)*Transform2D(residual_a.x.lerp(residual_b.x,t),residual_a.y.lerp(residual_b.y,t),Vector2.ZERO)
	basis.origin=anchor-basis.basis_xform(dimensions*pivot)
	return {"transform":basis,"dimensions":dimensions,"opacity":lerpf(a.artwork.opacity if a.artwork.visible else 0.,b.artwork.opacity if b.artwork.visible else 0.,t)}
func mesh_for(mapping: Dictionary, extent: Vector2) -> ArrayMesh:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); var positions := PackedVector3Array(); var colors := PackedColorArray()
	for i in mapping.uv_a.size():
		var uv: Vector2=mapping.uv_a[i]; var target: Vector2=mapping.uv_b[i]; positions.append(Vector3(uv.x*extent.x,uv.y*extent.y,0))
		var hi := (target*255.).floor()/255.; var lo := (target-hi)*255.; colors.append(Color(hi.x,hi.y,lo.x,lo.y))
	arrays[Mesh.ARRAY_VERTEX]=positions; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_TEX_UV]=mapping.uv_a; arrays[Mesh.ARRAY_INDEX]=mapping.indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh
func sync(session: KiwiTransformationSession, time: float, samples: Dictionary = {}) -> void:
	viewport.size=session.document.canvas_size; var live := {}; status=""
	for item in session.document.components:
		live[item.id]=true
		if not views.has(item.id):
			var node := MeshInstance2D.new(); var material := ShaderMaterial.new(); material.shader=shader; node.material=material; viewport.add_child(node); views[item.id]={"node":node,"signature":""}
		var view: Dictionary=views[item.id]; var node: MeshInstance2D=view.node; viewport.move_child(node,viewport.get_child_count()-1)
		var event_state := KiwiMorphComponentEvents.evaluate(session.document,item.id,time)
		if not item.visible or not event_state.visible: node.visible=false; continue
		var sample: Dictionary = samples[item.id] if samples.has(item.id) else session.sampled(item,time); var a: KiwiTransformationState=sample.a; var b: KiwiTransformationState=sample.b; var key: KiwiTransformationKey=sample.key
		if a==null or b==null: node.visible=false; continue
		var t := float(sample.t); var mode := key.mode if key!=null else "Step"; var mapping := KiwiTransformationMorph.identity(); var morph := false; var growth := 0; var reveal_replace := false; var prepared: Dictionary={}
		if a!=b and mode not in ["Step","Crossfade"]:
			var pair_id := cache.signature(a,b,key)
			if view.get("pair_id","")!=pair_id: view.pair_id=pair_id; view.prepared={}
			prepared=view.get("prepared",{})
			if prepared.is_empty():
				prepared=cache.get_pair(a,b,key)
				if not prepared.is_empty(): view.prepared=prepared
			if prepared.is_empty(): status="Preparing morph… temporary crossfade preview."
			else:
				if prepared.empty_a!=prepared.empty_b: growth=1 if prepared.empty_a else -1
				elif mode in ["Reveal","Grow / Reveal"]: growth=1; reveal_replace=true
				elif prepared.valid: mapping=prepared; morph=true; status=prepared.get("method","")+" · "+prepared.reason if not prepared.reason.is_empty() and prepared.reason!="Crossfade" else prepared.get("method","")
				else: status=prepared.reason
		var settings := transform_at(a,b,t,key.turns if key!=null else 0); var signature := str(hash([mapping.uv_a,mapping.uv_b,mapping.indices,a.artwork.dimensions,b.artwork.dimensions]))
		if view.signature!=signature: node.mesh=mesh_for(mapping,a.artwork.dimensions.max(b.artwork.dimensions)); view.signature=signature
		node.transform=settings.transform; node.visible=item.visible and float(settings.opacity)>.00001
		var material := node.material as ShaderMaterial
		material.set_shader_parameter("mask_count",event_state.masks.size())
		for i in event_state.masks.size(): material.set_shader_parameter("transfer_mask"+str(i),event_state.masks[i])
		var fields := prepared.has("field_a") and prepared.has("field_b")
		material.set_shader_parameter("has_fields",fields); material.set_shader_parameter("implicit_shape",morph and prepared.get("topology",false)); material.set_shader_parameter("feature_appearance",key!=null and key.appearance=="Feature reveal" and mode!="Crossfade"); material.set_shader_parameter("topology_bias",key.topology_bias if key!=null else 0.)
		if fields: material.set_shader_parameter("field_a",prepared.field_a); material.set_shader_parameter("field_b",prepared.field_b)
		var origin := key.morph_origin if key!=null and key.origin_enabled else (b.pivot if growth==1 else a.pivot)
		var reveal_kind := ["Point","Path","Directional","Shape expansion"].find(key.reveal_mode) if key!=null else 0
		if key!=null and mode=="Reveal" and key.reveal_path.size()>1: reveal_kind=1
		material.set_shader_parameter("reveal_kind",reveal_kind); material.set_shader_parameter("direction",Vector2.from_angle(deg_to_rad(key.direction)) if key!=null else Vector2.DOWN)
		var bounds: Rect2=prepared.get("bounds_b" if growth==1 else "bounds_a",Rect2(Vector2.ZERO,Vector2.ONE)); var radius := .001
		for point in [bounds.position,bounds.end,Vector2(bounds.end.x,bounds.position.y),Vector2(bounds.position.x,bounds.end.y)]: radius=maxf(radius,origin.distance_to(point))
		material.set_shader_parameter("growth_radius",radius)
		material.set_shader_parameter("reveal_replace",reveal_replace)
		material.set_shader_parameter("image_a",a.artwork.texture); material.set_shader_parameter("image_b",b.artwork.texture); material.set_shader_parameter("progress",t); material.set_shader_parameter("morph",t if morph else 0.); material.set_shader_parameter("dimensions",settings.dimensions); material.set_shader_parameter("opacity",settings.opacity); material.set_shader_parameter("growth",growth); material.set_shader_parameter("origin",origin)
		var path := key.reveal_path if key!=null else PackedVector2Array(); var buffer := PackedVector2Array(); buffer.resize(64)
		for i in path.size(): buffer[i]=path[i]
		material.set_shader_parameter("path_count",path.size()); material.set_shader_parameter("path_points",buffer); material.set_shader_parameter("path_width",key.reveal_width if key!=null else .3)
	for id in views.keys():
		if not live.has(id): views[id].node.free(); views.erase(id)
func flattened() -> Image:
	# Convert the premultiplied viewport to straight-alpha native pixels on GPU.
	var output := SubViewport.new(); output.world_2d=World2D.new(); output.size=viewport.size; output.disable_3d=true; output.transparent_bg=true; add_child(output)
	var display := TextureRect.new(); display.texture=texture(); display.size=Vector2(output.size); output.add_child(display)
	var material := ShaderMaterial.new(); var conversion := Shader.new(); conversion.code="shader_type canvas_item; render_mode unshaded,blend_disabled; void fragment(){vec4 c=texture(TEXTURE,UV);COLOR=vec4(c.rgb/max(c.a,.00001),c.a);}"
	material.shader=conversion; display.material=material; output.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	for i in 3: await RenderingServer.frame_post_draw
	var image := output.get_texture().get_image(); output.queue_free(); return image
