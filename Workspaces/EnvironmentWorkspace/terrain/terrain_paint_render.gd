extends RefCounted
## Reuses native material assets. Shader materials keep their own authored shader;
## native PBR surfaces can blend continuously with triplanar color and normals.
static func material(owner: Node3D,terrain: KiwiEnvironmentTerrain,ground: Material,paint: Material) -> Material:
	if not ground is BaseMaterial3D or not paint is BaseMaterial3D: return null
	var key:=hash([terrain.dimensions,terrain.resolution,terrain.material_mask,KiwiEnvironmentAssets.content_stamp(ground),KiwiEnvironmentAssets.content_stamp(paint)])
	if owner.get_meta("paint_render_key",-1)==key: return owner.get_meta("paint_render_material") as Material
	var source:=Image.create_from_data(terrain.resolution,terrain.resolution,false,Image.FORMAT_RF,terrain.material_mask.to_byte_array()); source.generate_mipmaps()
	var result:=owner.get_meta("paint_render_material") as ShaderMaterial if owner.has_meta("paint_render_material") else null
	if result==null: result=ShaderMaterial.new(); result.shader=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint.gdshader")
	var texture:=result.get_shader_parameter("paint_mask") as ImageTexture
	if texture!=null and texture.get_size()==Vector2(terrain.resolution,terrain.resolution): texture.update(source)
	else: texture=ImageTexture.create_from_image(source)
	result.set_shader_parameter("paint_mask",texture); result.set_shader_parameter("terrain_size",terrain.dimensions)
	for index in 2:
		var native: BaseMaterial3D=ground if index==0 else paint; var prefix:="ground_" if index==0 else "paint_"
		for pair in [["color",native.albedo_color],["texture",native.albedo_texture],["normal",native.normal_texture],["scale",native.uv1_scale],["offset",native.uv1_offset],["roughness",native.roughness],["metallic",native.metallic],["normal_strength",native.normal_scale if native.normal_enabled else 0.],["roughness_texture",native.roughness_texture],["metallic_texture",native.metallic_texture]]: result.set_shader_parameter(prefix+str(pair[0]),pair[1])
		var channels: Array[Vector4]=[Vector4(1,0,0,0),Vector4(0,1,0,0),Vector4(0,0,1,0),Vector4(0,0,0,1),Vector4(1./3.,1./3.,1./3.,0)]
		result.set_shader_parameter(prefix+"roughness_channel",channels[clampi(native.roughness_texture_channel,0,4)]); result.set_shader_parameter(prefix+"metallic_channel",channels[clampi(native.metallic_texture_channel,0,4)])
	owner.set_meta("paint_render_key",key); owner.set_meta("paint_render_material",result); return result
