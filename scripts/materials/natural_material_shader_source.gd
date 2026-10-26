extends RefCounted
## Specialization removes unused families before driver compilation. This prevents
## exponential GLSL inlining on ordinary integrated/Compatibility graphics drivers.
const Definitions=preload("res://scripts/materials/natural_material_definitions.gd")
const FUNCTIONS=["nm_metal","nm_wood","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"]
const SYMBOLS=["seamless","family","variant","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","primary","secondary","h","n","cell","line","pattern","raw_pattern","natural_color","natural_surface","nm_fbm","nm_threads","nm_wood","nm_metal","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"]
const PATTERN_SOURCE=preload("res://scripts/materials/natural_material_pattern.gdshaderinc")
static var source: String=PATTERN_SOURCE.code

static func family_index(id: String) -> int:
	return maxi(0,Definitions.CATEGORIES.keys().find(Definitions.category(id)))

static func pattern_source(id: String) -> String:
	var result:=source
	var selected: String=FUNCTIONS[family_index(id)]
	for function in FUNCTIONS:
		if function!=selected: result=replace_function(result,"float "+function+"(","")
	var body:="float raw_pattern(vec2 p){p*=max(.01,density);float v=%s(p);return clamp((v-.5)*contrast+.5+brightness,0.,1.);}" % selected
	result=replace_function(result,"float raw_pattern(",body)
	return result

static func secondary_source(id: String) -> String:
	var result:=pattern_source(id)
	for symbol in SYMBOLS:
		var expression:=RegEx.new();expression.compile("\\b"+symbol+"\\b")
		result=expression.sub(result,"secondary_"+symbol,true)
	return result

static func replace_function(code: String,marker: String,replacement: String) -> String:
	var start:=code.find(marker)
	if start<0: return code
	var opening:=code.find("{",start)
	var end:=block_end(code,opening)
	return code.substr(0,start)+replacement+code.substr(end+1)

static func block_end(code: String,opening: int) -> int:
	var depth:=0
	for index in range(opening,code.length()):
		if code[index]=="{": depth+=1
		elif code[index]=="}":
			depth-=1
			if depth==0: return index
	return code.length()-1

static func constants(code: String,id: String,prefix: String="") -> String:
	var expression:=RegEx.new()
	expression.compile("uniform int "+prefix+"family=\\d+;")
	code=expression.sub(code,"const int "+prefix+"family="+str(family_index(id))+";",true)
	expression.compile("uniform int "+prefix+"variant=\\d+;")
	return expression.sub(code,"const int "+prefix+"variant="+str(Definitions.variant(id))+";",true)
