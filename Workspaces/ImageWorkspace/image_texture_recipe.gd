class_name KiwiImageTextureRecipe
extends Resource
## Editable offline generator. Noise configuration uses the existing noise object.
@export var kind:="fractal"
@export var settings: Dictionary={"frequency":.035,"scale":1.0,"contrast":1.0,"brightness":0.0,"density":.5,"roughness":.5,"octaves":4,"rotation":0.0,"seed":0,"seamless":true,"invert":false,"primary":Color(.15,.2,.25),"secondary":Color(.85,.9,.95)}
@export var noise_object: ActorObjectData

func copy_recipe() -> KiwiImageTextureRecipe:
	var result:=KiwiImageTextureRecipe.new(); result.kind=kind; result.settings=settings.duplicate(true)
	if noise_object!=null: result.noise_object=noise_object.copy_object()
	return result

func configure_noise() -> FastNoiseLite:
	if noise_object==null: noise_object=ActorObjectData.new(); noise_object.type_id=&"noise_image"
	noise_object.values={&"seed":int(settings.get("seed",0)),&"frequency":float(settings.get("frequency",.035)),&"octaves":int(settings.get("octaves",4)),&"gain":float(settings.get("roughness",.5)),&"noise_type":FastNoiseLite.TYPE_PERLIN if kind=="perlin" else (FastNoiseLite.TYPE_CELLULAR if kind in ["cellular","stone"] else FastNoiseLite.TYPE_SIMPLEX_SMOOTH)}
	var noise:=FastNoiseLite.new(); noise.seed=noise_object.get_value(&"seed",0); noise.frequency=noise_object.get_value(&"frequency",.035)
	noise.noise_type=noise_object.get_value(&"noise_type",FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	noise.fractal_octaves=noise_object.get_value(&"octaves",4); noise.fractal_gain=noise_object.get_value(&"gain",.5)
	noise.fractal_type=FastNoiseLite.FRACTAL_FBM if kind not in ["white","smooth","perlin","simplex"] else FastNoiseLite.FRACTAL_NONE
	return noise
