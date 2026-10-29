extends RefCounted
## Derived CPU geometry only. Each consumer receives an independent editable copy.
const LIMIT=64*1024*1024
static var _entries: Dictionary={}
static var _order: Array[String]=[]
static var _bytes:=0
static var _hits:=0
static var _misses:=0
static var _mutex:=Mutex.new()
static func mesh(kind: String,fields: Array,build: Callable) -> KiwiModelMesh:
	var digest:=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(fields)); var key:=kind+":"+digest.finish().hex_encode(); _mutex.lock()
	if _entries.has(key):
		_hits+=1; _order.erase(key); _order.append(key); var cached: KiwiModelMesh=_entries[key].mesh.copy_mesh(); _mutex.unlock(); return cached
	_misses+=1; _mutex.unlock(); var result: KiwiModelMesh=build.call()
	if result==null: return null
	var bytes:=result.vertices.size()*12+result.materials.size()*4
	for face in result.faces: bytes+=face.size()*4+32
	for uv in result.uv: bytes+=uv.size()*8+32
	_mutex.lock()
	if bytes<=LIMIT and not _entries.has(key):
		while not _order.is_empty() and (_bytes+bytes>LIMIT or _order.size()>=256):
			var oldest: String=_order.pop_front(); _bytes-=int(_entries[oldest].bytes); _entries.erase(oldest)
		_entries[key]={"mesh":result.copy_mesh(),"bytes":bytes}; _bytes+=bytes; _order.append(key)
	_mutex.unlock(); return result
static func clear() -> void:
	_mutex.lock(); _entries.clear(); _order.clear(); _bytes=0; _hits=0; _misses=0; _mutex.unlock()
static func statistics() -> Dictionary:
	_mutex.lock(); var result:={"bytes":_bytes,"entries":_entries.size(),"hits":_hits,"misses":_misses}; _mutex.unlock(); return result
