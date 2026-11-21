extends RefCounted
## One material definition and evaluator, adapted to 2D coverage, generated maps and 3D.
const Definitions=preload("res://scripts/materials/NaturalMaterialCatalog.cs")
const CanvasRenderer=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
const MATERIAL_FIELDS=["label","texture_size","rotation","relief","relief_softness","light_direction","highlight","shadow","alignment","mapping_origin","tint_strength","tiling","blending","metallic","image","mix_amount","mix_distribution","mix_mask"]
const PARAMETERS=["family","variant","primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","seamless","texture_size","angle","relief","metallic_override","image_map","imported","image_aspect","tint_strength"]
const ShaderSource=preload("res://scripts/materials/natural_material_shader_source.gd")
static var _spatial_shaders: Dictionary={}
static var _maps_cache: Dictionary={}
static var _map_order: Array[String]=[]

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("natural_material_engine")

static func definitions() -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 result.assign(_native().definitions())
 return result

static func defaults(id: String="wood/oak") -> Dictionary:
 return _native().defaults(id)

static func normalize(settings: Dictionary) -> Dictionary:
 return _native().normalize(settings)

static func material_from_settings(settings: Dictionary) -> KiwiTextureMaterial:
 return _native().material_from_settings(settings)

static func settings_from_material(value: KiwiTextureMaterial) -> Dictionary:
 return _native().settings_from_material(value)

static func canvas_material(value: KiwiTextureMaterial,extent: Vector2,frame: Transform2D=Transform2D.IDENTITY,straight_output: bool=false) -> ShaderMaterial:
 return _native().canvas_material(value,extent,frame,straight_output)

static func create_spatial_material(settings: Dictionary) -> ShaderMaterial:
 return _native().create_spatial_material(settings)

static func spatial_material(value: KiwiTextureMaterial) -> ShaderMaterial:
 return _native().spatial_material(value)

static func configure_spatial(material: ShaderMaterial,settings: Dictionary) -> void:
 _native().configure_spatial(material,settings)

static func _spatial_source(value: KiwiTextureMaterial) -> String:
 return _native().spatial_source(value)

static func render_maps(host: Node,value: KiwiTextureMaterial,size: Vector2i=Vector2i(256,256),outputs: Array=["albedo"]) -> Dictionary:
 var result: Dictionary={}
 var request: Dictionary=_native().map_request(value,size)
 for output in outputs:
  var state: Dictionary=_native().prepare_map(host,value,request,output)
  if state.is_empty(): continue
  if state.has("image"):
   result[output]=state.image
   continue
  for frame in 3: await RenderingServer.frame_post_draw
  var image: Image=_native().complete_map(state)
  if image!=null: result[output]=image
 return result

static func clear_cache() -> void:
 _native().clear_cache()
