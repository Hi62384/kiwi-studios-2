extends RefCounted
## Field resources are reused by spatial density and appearance influences.
static var textures: Dictionary={}
static var texture_images: Dictionary={}
static var builds:=0
const MAX_CACHE:=32
const PAINT_SIZE:=32

const FIELD_ROWS := [
		["enabled","Enabled",true,{}],
		["mode","Field",0,{"choices":["Uniform","Height","Radial","Directional","3D noise","Painted / volume texture","Shape mask / composite","Closed mesh mask"]}],
		["combine","Combination",1,{"choices":["Add","Multiply","Maximum","Minimum","Subtract","Replace"]}],
		["target","Affect",0,{"choices":["Density","Color tint","Emission"]}],
		["color","Tint",Color.WHITE,{}],
		["strength","Strength",1.,{"min":0.,"max":8.}],
		["value","Uniform value",1.,{"min":0.,"max":16.}],
		["direction","Direction",Vector3.UP,{}],
		["start","Start",0.,{}], ["end","End",1.,{}],
		["falloff","Falloff",1.,{"min":.01,"max":16.}],
		["invert","Invert",false,{}],
		["world_space","World coordinates",false,{}],
		["scale","Scale",Vector3.ONE,{}], ["offset","Offset",Vector3.ZERO,{}],
		["shape","Mask shape",0,{"choices":["Box","Sphere","Ellipsoid","Cylinder","Cone","Capsule"]}],
		["shape_size","Mask size",Vector3.ONE,{"min":.001}],
		["shape_rotation","Mask rotation (°)",Vector3.ZERO,{}],
		["shape_edge","Mask edge softness",.05,{"min":.0001,"max":1.}],
		["noise_type","Noise",0,{"choices":["Smooth simplex","Perlin","Fractal","Ridged","Cellular","Domain warped"]}],
		["seed","Seed",1,{}], ["frequency","Frequency",3.,{"min":.01,"max":64.}],
		["octaves","Octaves",3,{"min":1,"max":8}], ["lacunarity","Lacunarity",2.,{"min":1.,"max":4.}],
		["gain","Gain",.5,{"min":0.,"max":1.}], ["contrast","Contrast",1.,{"min":.01,"max":16.}],
		["threshold","Threshold",0.,{"min":0.,"max":.99}],
		["resolution","Volume quality",1,{"choices":["Low · 16³","Balanced · 32³","High · 64³","Custom"]}],
		["custom_resolution","Custom volume resolution",32,{"min":8,"max":64,"visible_when":{"property":"resolution","values":[3]}}]
]
const PAINT_ROWS := [["brush_radius","Paint radius (voxels)",3.,{"min":.5,"max":16.}],["brush_strength","Paint strength",.5,{"min":0.,"max":1.}],["brush_falloff","Paint falloff",1.,{"min":0.,"max":4.}],["brush_tool","Paint operation",0,{"choices":["Add","Subtract","Set","Smooth","Reset"]}],["paint_plane","Editing plane",0,{"choices":["View","X","Y","Z"]}],["paint_depth","Plane depth",.5,{"min":0.,"max":1.}],["symmetry_x","Mirror X",false,{}],["symmetry_y","Mirror Y",false,{}],["symmetry_z","Mirror Z",false,{}]]

static func definition() -> ActorObjectDefinition:
	return _native().definition()

static func noise_for(v: Dictionary) -> FastNoiseLite:
	return _native().noise_for(v)

static func texture(v: Dictionary,as_mask: bool=false) -> Texture3D:
	return _native().texture(v,as_mask)

static func prepare_cpu(v: Dictionary,depth: int=0) -> Dictionary:
	return _native().prepare_cpu(v,depth)

static func sample_volume(images: Array[Image],point: Vector3,repeat: bool=true) -> float:
	return _native().sample_volume(images,point,repeat)

static func sample_prepared(source: Dictionary,unit: Vector3,world: Vector3) -> float:
	return _native().sample_prepared(source,unit,world)

static func mask_signature(v: Dictionary) -> int:
	return _native().mask_signature(v)

static func sample_mask(v: Dictionary,point: Vector3,noise: FastNoiseLite,paint: Dictionary,size: int,cloud: Dictionary={}) -> float:
	return _native().sample_mask(v,point,noise,paint,size,cloud)

static func shape_distance(p: Vector3,dimensions: Vector3,shape: int) -> float:
	return _native().shape_distance(p,dimensions,shape)

static func paint_dab(source: Dictionary,center: Vector3i,radius: float,strength: float,falloff: float,mode: int) -> Dictionary:
	return _native().paint_dab(source,center,radius,strength,falloff,mode)

static func combine(a: float,b: float,mode: int,strength: float) -> float:
	return _native().combine(a,b,mode,strength)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_field")
