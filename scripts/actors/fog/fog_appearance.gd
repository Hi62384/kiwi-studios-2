extends RefCounted
## Ordinary Kiwi objects: nested editing, keyframes, shared files and clipboard
## use the same paths as other materials. No separate animation system.
const PRESETS := ["Morning Mist","Dense Fog","Ground Haze","Dusty Atmosphere","Colored Fantasy Fog","Dark Cave Mist"]

static func definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"fog_appearance"; d.display_name="Fog Appearance"
	var rows:=[
		["cloud_lod","Distance detail reduction",false,"Cloud rendering",{"tooltip":"Smoothly blends the authored cloud source toward a cached 16³ rendering field. Simulated concentration retains its physical grid."}],
		["cloud_detail_distance","Full detail distance (m)",50.,"Cloud rendering",{"min":1.,"max":10000.}],
		["projected_shadow","Project cloud shadow",false,"Ground shadow",{"tooltip":"Local decal approximation from integrated density and the real sun. Receives on geometry within the chosen ground elevation/depth; requires Forward+."}],
		["shadow_ground","Receiver elevation (world m)",0.,"Ground shadow",{}],
		["shadow_depth","Receiver depth (m)",2.,"Ground shadow",{"min":.05,"max":1000.}],
		["shadow_strength","Projected shadow strength",.7,"Ground shadow",{"min":0.,"max":1.}],
		["shadow_resolution","Projection quality",0,"Ground shadow",{"choices":["Fast · 16²","Detailed · 32²"]}],
		["shadow_cull_mask","Receiver visual layers",1048575,"Ground shadow",{"min":0,"max":1048575}],
		["shadow_distance","Shadow fade distance (m)",100.,"Ground shadow",{"min":1.,"max":10000.}],
		["render_style","Rendering style",0,"Cloud rendering",{"choices":["Realistic","Cartoon","Anime","Painterly","Fantasy"]}],
		["stylization","Stylization amount",1.,"Cloud rendering",{"min":0.,"max":1.}],
		["shading_bands","Shading bands",3,"Cloud rendering",{"min":2,"max":8}],
		["shadow_tint","Shadow palette",Color(.35,.42,.55),"Cloud rendering",{}],
		["highlight","Highlight strength",1.,"Cloud rendering",{"min":0.,"max":4.}],
		["cloud_lighting","Cloud self-shadow approximation",false,"Cloud rendering",{"tooltip":"Six bounded density samples toward the strongest directional light. An artistic single-light approximation over native volumetric lighting, not full multiple scattering."}],
		["cloud_shadow_strength","Internal shadow strength",1.,"Cloud rendering",{"min":0.,"max":4.}],
		["silver_lining","Backlit silver lining",0.,"Cloud rendering",{"min":0.,"max":8.}],
		["title","Name","Fog Appearance","Preset",{}],
		["color","Base color",Color.WHITE,"Color",{}],
		["secondary","Secondary color",Color(.65,.8,1),"Color",{}],
		["third_color","Third color",Color(.7,.6,1),"Color",{}],
		["fourth_color","Fourth color",Color.WHITE,"Color",{}],
		["gradient_stops","Color stops",2,"Color",{"min":2,"max":4}],
		["stop_2","Second stop position",.33,"Color",{"min":0.,"max":1.}],
		["stop_3","Third stop position",.66,"Color",{"min":0.,"max":1.}],
		["gradient","Gradient",0,"Color",{"choices":["Solid","Vertical","Horizontal","Radial","Directional"]}],
		["direction","Gradient direction",Vector3.UP,"Color",{}],
		["gradient_start","Gradient start",0.,"Color",{}],
		["gradient_end","Gradient end",1.,"Color",{}],
		["gradient_falloff","Gradient falloff",1.,"Color",{"min":.01,"max":16.}],
		["world_space","World mapping",false,"Mapping",{}],
		["density_multiplier","Density multiplier",1.,"Optical",{"min":0.,"max":64.}],
		["contrast","Density contrast",1.,"Optical",{"min":.01,"max":16.}],
		["offset","Density offset",0.,"Optical",{"min":-16.,"max":16.}],
		["threshold","Density threshold",0.,"Optical",{"min":0.,"max":16.}],
		["maximum","Density maximum",64.,"Optical",{"min":0.,"max":128.}],
		["opacity","Opacity / extinction",1.,"Optical",{"min":0.,"max":1.,"tooltip":"Multiplies extinction. Longer paths through fog still attenuate more strongly."}],
		["scattering","Scattering albedo",1.,"Optical",{"min":0.,"max":1.,"tooltip":"Fraction of extinguished light scattered; the remainder is absorbed."}],
		["absorption","Additional absorption",0.,"Optical",{"min":0.,"max":16.,"tooltip":"Adds extinction while preserving the scattering coefficient."}],
		["emission","Emission",Color.BLACK,"Optical",{}],
		["emission_energy","Emission energy",1.,"Optical",{"min":0.,"max":64.}],
		["texture_scale","Texture scale",Vector3.ONE,"Mapping",{}],
		["texture_offset","Texture offset",Vector3.ZERO,"Mapping",{}],
		["texture_rotation","Texture rotation (°)",Vector3.ZERO,"Mapping",{}],
		["texture_mapping","2D mapping",0,"Mapping",{"choices":["Planar XY","Triplanar"]}],
		["texture_strength","Texture strength",1.,"Mapping",{"min":0.,"max":1.}]
		,["texture_contrast","Texture contrast",1.,"Mapping",{"min":.01,"max":16.}]
		,["texture_tiling","Tile textures",true,"Mapping",{}]
	]
	for row in rows:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[4]); p.options.group=row[3]; d.properties.append(p)
	for key in ["color_texture","density_texture","mask_texture","detail_texture"]:
		var p:=ActorProperty.create(StringName(key),key.capitalize(),null); p.object_type=&"image"; p.options.merge({"group":"Textures","accepted_object_types":["image","noise_image"]}); d.properties.append(p)
	for key in ["density_volume","color_volume"]:
		var p:=ActorProperty.create(StringName(key),key.capitalize(),""); p.options.merge({"group":"Textures","file_picker":true,"extensions":["tres","res"],"native_resource_types":["Texture3D"],"file_resource_mode":"uneditable"}); d.properties.append(p)
	for index in 4:
		var p:=ActorProperty.create(StringName("layer_%d"%index),"Appearance influence %d"%(index+1),null); p.object_type=&"fog_field"; p.options.group="Layers"; d.properties.append(p)
	return d

static func preset(index: int) -> ActorObjectData:
	var data:=definition().create_object(); index=clampi(index,0,PRESETS.size()-1)
	data.values[&"title"]=PRESETS[index]
	data.values[&"color"]=[Color("edf3ff"),Color("bbc3c9"),Color("c5d8e9"),Color("ad8d6d"),Color("768bff"),Color("3d4b58")][index]
	data.values[&"density_multiplier"]=[.12,2.,.2,.45,.65,.8][index]
	if index==4: data.values[&"gradient"]=1; data.values[&"secondary"]=Color("bc64e8")
	var field:=preload("res://scripts/actors/fog/fog_field.gd").definition().create_object(); field.values[&"mode"]=4; field.values[&"strength"]=[.15,.45,.2,.6,.3,.7][index]
	data.values[&"layer_0"]=ActorObjectReference.from_object(field)
	if index==2:
		var height:=preload("res://scripts/actors/fog/fog_field.gd").definition().create_object(); height.values[&"mode"]=1; height.values[&"invert"]=true; data.values[&"layer_1"]=ActorObjectReference.from_object(height)
	return data

static func optical_density(field: float,values: Dictionary) -> float:
	var d:=maxf(0.,field+float(values.get(&"offset",0.))-float(values.get(&"threshold",0.)))
	d=pow(d,clampf(float(values.get(&"contrast",1.)),.01,16.))*maxf(0.,float(values.get(&"density_multiplier",1.)))
	d*=clampf(float(values.get(&"opacity",1.)),0.,1.)*(1.+maxf(0.,float(values.get(&"absorption",0.))))
	return clampf(d,0.,float(values.get(&"maximum",64.))) if is_finite(d) else 0.
