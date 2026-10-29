extends Resource
const SHADER_CACHE_LIMIT=32
const SHADER_CODE_BUDGET=4*1024*1024
static var _prepared: Dictionary={}
static var _shader_order: Array[String]=[]
static var _shader_bytes:=0
## Weak runtime binding; no authoring resource is modified or retained by a copy.
var _source: WeakRef
var _target: WeakRef
var _shader: WeakRef
var _code:=""
var _compiled:=false
var _uniforms:=PackedStringArray()
var _busy:=false
func active() -> bool: return _source!=null and _source.get_ref()!=null and _target!=null and _target.get_ref()!=null
func active_for(material: Material) -> bool: return active() and _target.get_ref()==material
func authoring_source() -> ShaderMaterial: return _source.get_ref() as ShaderMaterial if _source!=null else null
func setup(source: ShaderMaterial,target: ShaderMaterial) -> void:
	_source=weakref(source); _target=weakref(target); source.changed.connect(_changed); _changed()
func _changed() -> void:
	if _busy or not active(): return
	_busy=true; var source:=_source.get_ref() as ShaderMaterial; var target:=_target.get_ref() as ShaderMaterial; var previous:=_shader.get_ref() as Shader if _shader!=null else null
	if previous!=source.shader:
		if previous!=null and previous.changed.is_connected(_changed): previous.changed.disconnect(_changed)
		_shader=weakref(source.shader) if source.shader!=null else null
		if source.shader!=null: source.shader.changed.connect(_changed)
		_compiled=false
	if source.shader==null:
		target.shader=null; target.set_meta("kiwi_time_uniform",""); _uniforms=PackedStringArray(); _busy=false; return
	if not _compiled or _code!=source.shader.code:
		_compiled=true; _code=source.shader.code; var prepared:=_prepared_shader(source.shader); target.shader=prepared.shader; var uniform:=str(prepared.uniform)
		_uniforms=prepared.uniforms
		if uniform.is_empty():
			var existing:=str(source.get_meta("kiwi_time_uniform",""))
			if _uniforms.has(existing): uniform=existing
		target.set_meta("kiwi_time_uniform",uniform)
		if not uniform.is_empty(): target.set_shader_parameter(uniform,float(target.get_meta("kiwi_last_time",0.)))
	_busy=false; synchronize_parameters()
static func _prepared_shader(source: Shader) -> Dictionary:
	var code:=source.code
	if _prepared.has(code): _shader_order.erase(code); _shader_order.append(code); return _prepared[code]
	var transformed:=ActorShaderTime.prepare(code); var shader:=Shader.new(); shader.code=transformed.code; var uniforms:=PackedStringArray()
	for info: Dictionary in source.get_shader_uniform_list(): uniforms.append(str(info.name))
	var result:={"shader":shader,"uniform":str(transformed.uniform),"uniforms":uniforms,"bytes":code.length()*2+str(transformed.code).length()*2}
	if result.bytes<=SHADER_CODE_BUDGET:
		while not _shader_order.is_empty() and (_shader_order.size()>=SHADER_CACHE_LIMIT or _shader_bytes+int(result.bytes)>SHADER_CODE_BUDGET):
			var oldest: String=_shader_order.pop_front(); _shader_bytes-=int(_prepared[oldest].bytes); _prepared.erase(oldest)
		_prepared[code]=result; _shader_order.append(code); _shader_bytes+=int(result.bytes)
	return result
func synchronize_parameters() -> void:
	if _busy or not active(): return
	var source:=_source.get_ref() as ShaderMaterial; var target:=_target.get_ref() as ShaderMaterial
	if source.shader!=(_shader.get_ref() as Shader if _shader!=null else null): _changed(); return
	if target.shader==null: return
	var manual:=str(target.get_meta("kiwi_time_uniform",""))
	for name in _uniforms:
		if name==manual: continue
		var value: Variant=source.get_shader_parameter(name)
		if target.get_shader_parameter(name)!=value: target.set_shader_parameter(name,value)
