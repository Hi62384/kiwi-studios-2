extends RefCounted
## Ground, paint and a renderer-bounded biome palette, shared with scatter fields.
const MAX_BIOME_MATERIALS:=8
static var _shader: Shader
static var _material_capacity:=-1
static func capacity() -> int:
	if _material_capacity>0: return _material_capacity
	var device:=RenderingServer.get_rendering_device(); _material_capacity=4
	if device!=null:
		var limit:=device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURES_PER_SHADER_STAGE)
		if limit<0 or limit>=64: _material_capacity=MAX_BIOME_MATERIALS
	return _material_capacity
static func material(owner: Node3D,terrain: KiwiEnvironmentTerrain,ground: Material,paint: Material) -> Material:
	owner.set_meta("biome_material_warnings",PackedStringArray())
	if terrain.biomes==null or terrain.biome_data.is_empty() or not ground is BaseMaterial3D: return null
	var layers: Array[Dictionary]=[]; var warnings:=PackedStringArray()
	for definition in terrain.biomes.definitions:
		if not definition.get("enabled",true): continue
		var sources: Array=definition.get("materials",[]); var accepted: Array[Dictionary]=[]; var total:=0.
		for source in sources:
			var value: Variant=source.get("source") if source is Dictionary else source; var native:=KiwiEnvironmentAssets.material(value)
			if not native is BaseMaterial3D: warnings.append("Biome %s needs a native PBR material for surface blending."%str(definition.get("name",""))); continue
			var weight:=maxf(0.,float(source.get("weight",1.))) if source is Dictionary else 1.; total+=weight; accepted.append({"id":str(definition.id),"source":native,"weight":weight})
		for entry in accepted:
			if layers.size()==capacity(): warnings.append("Biome material budget reached (%d surfaces on this renderer). Split terrain or reduce its material palette."%capacity()); break
			entry.weight=float(entry.weight)/maxf(.000001,total); layers.append(entry)
	owner.set_meta("biome_material_warnings",warnings)
	if layers.is_empty(): return null
	var natives: Array[BaseMaterial3D]=[ground,paint if paint is BaseMaterial3D else ground]
	for layer in layers: natives.append(layer.source)
	var stamps:=[]
	for native in natives: stamps.append(KiwiEnvironmentAssets.content_stamp(native))
	var key:=hash([terrain.dimensions,terrain.resolution,terrain.material_mask,terrain.biome_key,terrain.cave_biome_key,terrain.biome_data.get("preview_revision",0),terrain.biomes.signature(),stamps])
	if owner.get_meta("biome_render_key",-1)==key: return owner.get_meta("biome_render_material")
	var result:=owner.get_meta("biome_render_material") as ShaderMaterial if owner.has_meta("biome_render_material") else null
	if result==null: result=ShaderMaterial.new(); result.shader=shader()
	var count:=terrain.resolution*terrain.resolution; var layer_count:=capacity()+2; var map_count:=ceili(float(layer_count)/4.); var channels: Array[PackedFloat32Array]=[]
	for texture in map_count: var values:=PackedFloat32Array(); values.resize(count*4); channels.append(values)
	for index in count:
		var painted:=clampf(terrain.material_mask[index],0.,1.) if paint is BaseMaterial3D else 0.; var values:=PackedFloat32Array(); values.resize(layer_count); values[1]=painted; var biome_total:=0.
		for layer in layers.size():
			var weights: PackedFloat32Array=terrain.biome_data.get("weights",{}).get(str(layers[layer].id),PackedFloat32Array()); var weight: float=weights[index]*float(layers[layer].weight) if weights.size()==count else 0.; values[layer+2]=(1.-painted)*weight; biome_total+=weight
		values[0]=(1.-painted)*maxf(0.,1.-biome_total)
		for layer in layer_count: channels[layer/4][index*4+layer%4]=values[layer]
	for index in map_count:
		var image:=Image.create_from_data(terrain.resolution,terrain.resolution,false,Image.FORMAT_RGBAF,channels[index].to_byte_array()); image.generate_mipmaps(); var name:="weights%d"%index; var texture:=result.get_shader_parameter(name) as ImageTexture
		if texture!=null and texture.get_size()==Vector2(terrain.resolution,terrain.resolution): texture.update(image)
		else: texture=ImageTexture.create_from_image(image)
		result.set_shader_parameter(name,texture)
	result.set_shader_parameter("terrain_size",terrain.dimensions)
	for index in layer_count:
		var native:=natives[index] if index<natives.size() else ground as BaseMaterial3D; var prefix:="layer%d_"%index
		for pair in [["color",native.albedo_color],["texture",native.albedo_texture],["normal",native.normal_texture],["scale",native.uv1_scale],["offset",native.uv1_offset],["roughness",native.roughness],["metallic",native.metallic],["normal_strength",native.normal_scale if native.normal_enabled else 0.],["roughness_texture",native.roughness_texture],["metallic_texture",native.metallic_texture]]: result.set_shader_parameter(prefix+str(pair[0]),pair[1])
		var masks: Array[Vector4]=[Vector4(1,0,0,0),Vector4(0,1,0,0),Vector4(0,0,1,0),Vector4(0,0,0,1),Vector4(1./3.,1./3.,1./3.,0)]
		result.set_shader_parameter(prefix+"roughness_channel",masks[clampi(native.roughness_texture_channel,0,4)]); result.set_shader_parameter(prefix+"metallic_channel",masks[clampi(native.metallic_texture_channel,0,4)])
	_bind_cave(owner,result,terrain,layers)
	owner.set_meta("biome_render_key",key); owner.set_meta("biome_render_material",result); return result
static func _bind_cave(owner: Node3D,material: ShaderMaterial,terrain: KiwiEnvironmentTerrain,layers: Array[Dictionary]) -> void:
	var data:=terrain.cave_biome_data
	material.set_shader_parameter("has_cave_fields",false)
	if data.is_empty(): return
	var size: Vector3i=data.size; var images: Array=[]; var masks: Array[Image]=[]; var fields: Array[PackedFloat32Array]=[]; var multipliers:=PackedFloat32Array(); var maps:=ceili(float(capacity())/4.)
	for index in maps: var slices: Array[Image]=[]; images.append(slices)
	for layer in layers: fields.append(data.weights.get(str(layer.id),PackedFloat32Array())); multipliers.append(float(layer.weight))
	var presence: PackedByteArray=data.presence
	for z in size.z:
		var channels: Array[PackedFloat32Array]=[]
		for map in maps: var values:=PackedFloat32Array(); values.resize(size.x*size.y*4); channels.append(values)
		var mask:=PackedFloat32Array(); mask.resize(size.x*size.y)
		for index in size.x*size.y:
			var source:=index+z*size.x*size.y; mask[index]=float(presence[source])
			for layer in fields.size():
				if not fields[layer].is_empty(): channels[layer/4][index*4+layer%4]=fields[layer][source]*multipliers[layer]
		for map in maps: images[map].append(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,channels[map].to_byte_array()))
		masks.append(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RF,mask.to_byte_array()))
	var textures: Array=[["cave_presence",masks,Image.FORMAT_RF]]
	for map in maps: textures.append(["cave_weights"+str(map) if map>0 else "cave_weights",images[map],Image.FORMAT_RGBAF])
	for entry in textures:
		var texture:=material.get_shader_parameter(entry[0]) as ImageTexture3D
		if texture!=null and texture.get_width()==size.x and texture.get_height()==size.y and texture.get_depth()==size.z: texture.update(entry[1])
		else:
			texture=ImageTexture3D.new(); var error:=texture.create(entry[2],size.x,size.y,size.z,false,entry[1])
			if error!=OK: var warnings: PackedStringArray=owner.get_meta("biome_material_warnings",PackedStringArray()); warnings.append("This renderer could not upload the cave biome volume."); owner.set_meta("biome_material_warnings",warnings); return
		material.set_shader_parameter(entry[0],texture)
	material.set_shader_parameter("cave_origin",(data.origin as Vector3)-(data.spacing as Vector3)*.5); material.set_shader_parameter("cave_extent",Vector3(size)*(data.spacing as Vector3)); material.set_shader_parameter("has_cave_fields",true)
static func shader() -> Shader:
	if _shader!=null: return _shader
	var source: String=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint.gdshader").code; var start:=source.find("vec3 triplanar_color"); var end:=source.find("void fragment()")
	var code:="shader_type spatial;\nuniform vec2 terrain_size=vec2(32.0);\nuniform sampler2D weights0: filter_linear_mipmap, repeat_disable;\nuniform sampler2D weights1: filter_linear_mipmap, repeat_disable;\nuniform bool has_cave_fields=false;uniform sampler3D cave_weights:hint_default_black,filter_linear,repeat_disable;uniform sampler3D cave_presence:hint_default_black,filter_linear,repeat_disable;uniform vec3 cave_origin=vec3(0.0);uniform vec3 cave_extent=vec3(1.0);\nvarying vec3 local_position; varying vec3 local_normal; varying mat3 normal_to_view;\nvoid vertex(){local_position=VERTEX;local_normal=NORMAL;normal_to_view=mat3(VIEW_MATRIX)*MODEL_NORMAL_MATRIX;}\n"+source.substr(start,end-start)
	if capacity()>4: code+="uniform sampler2D weights2:filter_linear_mipmap,repeat_disable;uniform sampler3D cave_weights1:hint_default_black,filter_linear,repeat_disable;\n"
	for index in capacity()+2:
		var prefix:="layer%d_"%index
		code+="uniform sampler2D %stexture:source_color,hint_default_white,filter_linear_mipmap,repeat_enable;\n"%prefix
		code+="uniform sampler2D %snormal:hint_normal,filter_linear_mipmap,repeat_enable;\n"%prefix
		for name in ["roughness_texture","metallic_texture"]: code+="uniform sampler2D %s%s:hint_default_white,filter_linear_mipmap,repeat_enable;\n"%[prefix,name]
		code+="uniform vec4 %scolor:source_color=vec4(1.0);\nuniform vec3 %sscale=vec3(1.0);\nuniform vec3 %soffset=vec3(0.0);\n"%[prefix,prefix,prefix]
		for name in ["roughness_channel","metallic_channel"]: code+="uniform vec4 %s%s=vec4(1.0,0.0,0.0,0.0);\n"%[prefix,name]
		for pair in [["roughness","1.0"],["metallic","0.0"],["normal_strength","0.0"]]: code+="uniform float %s%s=%s;\n"%[prefix,pair[0],pair[1]]
	code+="void fragment(){vec3 normal=normalize(local_normal);vec3 weights=pow(abs(normal),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),0.00001);vec3 signs=sign(normal+vec3(0.000001));vec2 map_uv=local_position.xz/terrain_size+vec2(0.5);vec4 a=texture(weights0,map_uv);vec4 b=texture(weights1,map_uv);vec3 color=vec3(0.0);vec3 mapped=vec3(0.0);float roughness=0.0;float metallic=0.0;float total=0.0;\n"
	if capacity()>4: code+="vec4 c=texture(weights2,map_uv);\n"
	code+="if(has_cave_fields){vec3 uv=(local_position-cave_origin)/max(cave_extent,vec3(0.0001));float inside=step(0.0,uv.x)*step(0.0,uv.y)*step(0.0,uv.z)*step(uv.x,1.0)*step(uv.y,1.0)*step(uv.z,1.0);vec4 cave=texture(cave_weights,uv);float coverage=smoothstep(0.01,0.2,texture(cave_presence,uv).r)*inside;float paint=a.g;float amount=dot(cave,vec4(1.0));"
	if capacity()>4: code+="vec4 cave1=texture(cave_weights1,uv);amount+=dot(cave1,vec4(1.0));"
	code+="a=mix(a,vec4((1.0-paint)*(1.0-clamp(amount,0.0,1.0)),paint,(1.0-paint)*cave.r,(1.0-paint)*cave.g),coverage);"
	if capacity()>4: code+="b=mix(b,vec4((1.0-paint)*cave.b,(1.0-paint)*cave.a,(1.0-paint)*cave1.r,(1.0-paint)*cave1.g),coverage);c=mix(c,vec4((1.0-paint)*cave1.b,(1.0-paint)*cave1.a,0.0,0.0),coverage);}\n"
	else: code+="b=mix(b,vec4((1.0-paint)*cave.b,(1.0-paint)*cave.a,0.0,0.0),coverage);}\n"
	for index in capacity()+2:
		var p:="layer%d_"%index; var weight: String=["a","b","c"][index/4]+"."+["r","g","b","a"][index%4]
		code+="{float w=max(0.0,%s);if(w>0.00001){vec3 uv=local_position*%sscale+%soffset;color+=w*%scolor.rgb*triplanar_color(%stexture,uv,weights);roughness+=w*%sroughness*triplanar_value(%sroughness_texture,uv,weights,%sroughness_channel);metallic+=w*%smetallic*triplanar_value(%smetallic_texture,uv,weights,%smetallic_channel);mapped+=w*normalize(mix(normal,triplanar_normal(%snormal,uv,weights,signs),%snormal_strength));total+=w;}}\n"%[weight,p,p,p,p,p,p,p,p,p,p,p,p]
	code+="ALBEDO=color/max(total,0.00001);ROUGHNESS=roughness/max(total,0.00001);METALLIC=metallic/max(total,0.00001);NORMAL=normalize(normal_to_view*normalize(mapped));}\n"
	_shader=Shader.new(); _shader.code=code; return _shader
