extends RefCounted
const PRESETS := ["Morning Mist","Dense Fog","Ground Haze","Dusty Atmosphere","Colored Fantasy Fog","Dark Cave Mist"]
const FIELD_ROWS := [
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
static func definition() -> ActorObjectDefinition:
	return _native().definition()
static func preset(index: int) -> ActorObjectData:
	return _native().preset(index)
static func optical_density(field: float,values: Dictionary) -> float:
	return _native().optical_density(field,values)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_appearance")
