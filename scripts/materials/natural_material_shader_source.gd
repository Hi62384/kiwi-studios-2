extends RefCounted
## Specialization removes unused families before driver compilation. This prevents
## exponential GLSL inlining on ordinary integrated/Compatibility graphics drivers.
const Definitions=preload("res://scripts/materials/NaturalMaterialCatalog.cs")
const FUNCTIONS=["nm_metal","nm_wood","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"]
const SYMBOLS=["seamless","family","variant","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","primary","secondary","h","n","cell","line","pattern","raw_pattern","natural_color","natural_surface","nm_fbm","nm_threads","nm_wood","nm_metal","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"]
const PATTERN_SOURCE=preload("res://scripts/materials/natural_material_pattern.gdshaderinc")
static var source: String=PATTERN_SOURCE.code

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("natural_material_shader_source")

static func family_index(id: String) -> int:
 return _native().family_index(id)

static func pattern_source(id: String) -> String:
 return _native().pattern_source(source,id)

static func secondary_source(id: String) -> String:
 return _native().secondary_source(source,id)

static func replace_function(code: String,marker: String,replacement: String) -> String:
 return _native().replace_function(code,marker,replacement)

static func block_end(code: String,opening: int) -> int:
 return _native().block_end(code,opening)

static func constants(code: String,id: String,prefix: String="") -> String:
 return _native().constants(code,id,prefix)
