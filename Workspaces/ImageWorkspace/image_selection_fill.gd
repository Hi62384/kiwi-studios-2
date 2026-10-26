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
static func capture_local_mask(workspace: KiwiImageWorkspace,layer: KiwiImageLayer) -> Texture2D:
	var canvas:=workspace.canvas
	if canvas.selection==null: return null
	var corners:=PackedVector2Array()
	for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var world:=workspace.document.world_transform(layer)*layer.project_point(uv*layer.content_dimensions())
		var point: Vector2=canvas.selection_inverse_warp.call(world) if canvas.selection_inverse_warp.is_valid() else canvas.selection_inverse*world
		corners.append(point/Vector2(canvas.selection.get_size()))
	var rows:=canvas._selection_projection(corners)
	if rows.is_empty(): return null
	var inverse:=Basis(Vector3(rows[0].x,rows[1].x,rows[2].x),Vector3(rows[0].y,rows[1].y,rows[2].y),Vector3(rows[0].z,rows[1].z,rows[2].z)).inverse()
	var shader:=Shader.new(); shader.code=CODE.replace("COLOR=mix(texture(TEXTURE,UV),fill_color,coverage*fill_opacity);","COLOR=vec4(coverage);")
	var material:=ShaderMaterial.new(); material.shader=shader
	material.set_shader_parameter("row0",Vector3(inverse.x.x,inverse.y.x,inverse.z.x))
	material.set_shader_parameter("row1",Vector3(inverse.x.y,inverse.y.y,inverse.z.y))
	material.set_shader_parameter("row2",Vector3(inverse.x.z,inverse.y.z,inverse.z.z))
	material.set_shader_parameter("mask_texture",ImageTexture.create_from_image(canvas.selection))
	if layer.warp != null and layer.warp.enabled:
		material.set_shader_parameter("warped", true)
		material.set_shader_parameter("deformation", layer.warp.texture())
		material.set_shader_parameter("field_size", Vector2(layer.warp.grid_size))
	var extent:=layer.content_dimensions(); extent*=minf(1,2048/maxf(1,maxf(extent.x,extent.y)))
	var target:=SubViewport.new(); target.disable_3d=true; target.transparent_bg=true; target.size=Vector2i(extent.ceil()).max(Vector2i.ONE); target.render_target_update_mode=SubViewport.UPDATE_ALWAYS; workspace.add_child(target)
	var white:=Image.create(1,1,false,Image.FORMAT_RGBA8); white.fill(Color.WHITE)
	var display:=TextureRect.new(); display.texture=ImageTexture.create_from_image(white); display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; display.size=Vector2(target.size); display.material=material; target.add_child(display)
	for i in 3: await RenderingServer.frame_post_draw
	var result:=ImageTexture.create_from_image(target.get_texture().get_image()); target.queue_free(); return result

static func apply(workspace: KiwiImageWorkspace,color: Color) -> void:
	workspace._finish_pending()
	var layer:=workspace._main_layer(); var canvas:=workspace.canvas
	if layer==null or canvas.selection==null: workspace.status.text="Select pixels to fill first"; return
	if layer.kind not in ["image","paint","basic"]:
		workspace.status.text="Rasterize this layer before filling its individual pixels"; return
	if layer.texture==null or not workspace.document.can_edit(layer): return
	var corners:=PackedVector2Array()
	for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var world:=workspace.document.world_transform(layer)*layer.project_point(uv*layer.dimensions)
		var point: Vector2=canvas.selection_inverse_warp.call(world) if canvas.selection_inverse_warp.is_valid() else canvas.selection_inverse*world
		corners.append(point/Vector2(canvas.selection.get_size()))
	var rows:=canvas._selection_projection(corners)
	if rows.is_empty(): workspace.status.text="Cannot fill a collapsed layer transform"; return
	var inverse:=Basis(Vector3(rows[0].x,rows[1].x,rows[2].x),Vector3(rows[0].y,rows[1].y,rows[2].y),Vector3(rows[0].z,rows[1].z,rows[2].z)).inverse()
	var shader:=Shader.new(); shader.code=CODE
	var material:=ShaderMaterial.new(); material.shader=shader
	material.set_shader_parameter("row0",Vector3(inverse.x.x,inverse.y.x,inverse.z.x))
	material.set_shader_parameter("row1",Vector3(inverse.x.y,inverse.y.y,inverse.z.y))
	material.set_shader_parameter("row2",Vector3(inverse.x.z,inverse.y.z,inverse.z.z))
	material.set_shader_parameter("fill_color",preload("res://Workspaces/ImageWorkspace/image_values.gd").inverse_color(Color(color.r,color.g,color.b,1),layer))
	material.set_shader_parameter("fill_opacity",clampf(color.a,0,1))
	material.set_shader_parameter("mask_texture",ImageTexture.create_from_image(canvas.selection))
	if layer.warp!=null and layer.warp.enabled:
		material.set_shader_parameter("warped",true); material.set_shader_parameter("deformation",layer.warp.texture()); material.set_shader_parameter("field_size",Vector2(layer.warp.grid_size))
	var target:=SubViewport.new(); target.disable_3d=true; target.transparent_bg=true; target.size=Vector2i(layer.texture.get_size()); target.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	workspace.add_child(target)
	var display:=TextureRect.new(); display.texture=layer.texture; display.size=Vector2(target.size); display.material=material; target.add_child(display)
	var original:=layer.texture; var owner:=workspace.document
	for frame in 3: await RenderingServer.frame_post_draw
	var result:=target.get_texture().get_image(); target.queue_free()
	if workspace.document!=owner or workspace.document.layer_for_id(layer.id)!=layer or layer.texture!=original: return
	workspace._action(func(): layer.texture=ImageTexture.create_from_image(result))
	workspace.status.text="Selected pixels filled"
