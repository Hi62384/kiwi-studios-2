extends RefCounted
## One GPU pass fills the active raster's selected pixels, respecting layer,
## yaw, selection and warp transforms. History keeps the original texture.
const CODE="""shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform sampler2D deformation : filter_linear, repeat_disable;
uniform vec2 field_size=vec2(65.0);
uniform bool warped=false;
uniform vec4 fill_color=vec4(1.0);
uniform float fill_opacity=1.0;
uniform vec3 row0=vec3(1.0,0.0,0.0);
uniform vec3 row1=vec3(0.0,1.0,0.0);
uniform vec3 row2=vec3(0.0,0.0,1.0);
void fragment(){
 vec2 p=UV;
 if(warped){for(int i=0;i<6;i++){p=UV-texture(deformation,(clamp(p,vec2(0.0),vec2(1.0))*(field_size-1.0)+.5)/field_size).rg;}}
 vec3 v=vec3(p,1.0); float w=dot(row2,v);
 vec2 q=abs(w)>.000001 ? vec2(dot(row0,v),dot(row1,v))/w : vec2(-1.0);
 float coverage=all(greaterThanEqual(q,vec2(0.0))) && all(lessThanEqual(q,vec2(1.0))) ? texture(mask_texture,q).a : 0.0;
 COLOR=mix(texture(TEXTURE,UV),fill_color,coverage*fill_opacity);
}
"""
static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_selection_fill")
static func capture_local_mask(workspace:KiwiImageWorkspace,layer:KiwiImageLayer)->Texture2D:
 var request:Dictionary=_native().prepare_capture(workspace,layer)
 if request.is_empty():return null
 for frame in 3:await RenderingServer.frame_post_draw
 return _native().complete_capture(request)
static func apply(workspace:KiwiImageWorkspace,color:Color)->void:
 var request:Dictionary=_native().prepare_apply(workspace,color)
 if request.is_empty():return
 for frame in 3:await RenderingServer.frame_post_draw
 _native().complete_apply(workspace,request)
static func _selection_point(canvas:KiwiImageCanvas,world:Vector2)->Vector2:
 return canvas.selection_inverse_warp.call(world) if canvas.selection_inverse_warp.is_valid() else canvas.selection_inverse*world
