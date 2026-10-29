class_name KiwiPhysicsBakeCache
extends Resource
## Persistent chunked snapshots. Geometry/material Resources are interned once;
## compressed frames contain only indices, numbers and ordinary containers.
const CHUNK_FRAMES:=32
const MAX_BYTES:=67108864
const MAX_RAW_BYTES:=268435456
@export var resources: Array[Resource]=[]
@export var records: Array[Dictionary]=[]
@export var chunks: Array[Dictionary]=[]
@export var count:=0
@export var bytes:=0
@export var raw_bytes:=0
@export var resource_bytes:=0
@export var storage_root: String=""
@export var complete:=false
var error: String=""
var owned_files: Array[String]=[]
const MAX_STREAM_BYTES:=4294967296
const MAX_CHUNK_RAW:=16777216
func begin_stream(directory: String) -> String:
	storage_root=ProjectSettings.globalize_path(directory).path_join("bake-"+ActorData.new_id()).simplify_path()
	if DirAccess.make_dir_recursive_absolute(storage_root)!=OK: return "Cannot create bake cache directory."
	return ""
static func digest(data: PackedByteArray) -> String:
	var context:=HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(data); return context.finish().hex_encode()
var pending: Array=[]
var pending_bytes:=0
var resource_indices: Dictionary={}
var record_indices: Dictionary={}
var decoded: Dictionary={}
func encode(value: Variant,key: String="") -> Variant:
	if value is Resource:
		var instance: int=value.get_instance_id()
		if not resource_indices.has(instance):
			resource_indices[instance]=resources.size(); resources.append(value)
			if value is KiwiModelMesh:
				resource_bytes+=value.vertices.size()*12+value.materials.size()*4
				for face: PackedInt32Array in value.faces: resource_bytes+=face.size()*12+64
			elif value is Mesh:
				for surface in value.get_surface_count(): resource_bytes+=var_to_bytes(value.surface_get_arrays(surface)).size()
			else: resource_bytes+=1024
		return {"@resource":resource_indices[instance]}
	if value is Dictionary:
		if key=="destruction_geometry":
			var identity: Variant=value.get("key",hash(value))
			if not record_indices.has(identity): record_indices[identity]=records.size(); records.append(encode(value,"record"))
			return {"@record":record_indices[identity]}
		var result:={}
		for child: Variant in value: result[child]=encode(value[child],str(child))
		return result
	if value is Array:
		var result:=[]
		for child: Variant in value: result.append(encode(child))
		return result
	return value
func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("@resource"): return resources[int(value["@resource"])]
		if value.has("@record"): return decode(records[int(value["@record"])])
		var result:={}
		for key: Variant in value: result[key]=decode(value[key])
		return result
	if value is Array:
		var result:=[]
		for child: Variant in value: result.append(decode(child))
		return result
	return value
func append(frame: Dictionary) -> String:
	var encoded: Variant=encode(frame); var size:=var_to_bytes(encoded).size()+16
	if size>MAX_CHUNK_RAW: return "A single bake frame exceeds the 16 MiB chunk budget. Lower simulation resolution."
	if not pending.is_empty() and pending_bytes+size>MAX_CHUNK_RAW-1024:
		var result:=flush()
		if not result.is_empty(): return result
	pending.append(encoded); pending_bytes+=size; count+=1
	if resource_bytes>MAX_BYTES or (storage_root.is_empty() and bytes+resource_bytes>MAX_BYTES): return "Bake exceeds the 64 MiB resident geometry/data budget. Nothing was replaced."
	return flush() if pending.size()>=CHUNK_FRAMES else ""
func flush() -> String:
	if pending.is_empty(): return ""
	var raw:=var_to_bytes(pending); raw_bytes+=raw.size()
	if raw.size()>MAX_CHUNK_RAW: return "A bake chunk exceeds the 16 MiB resident chunk limit. Lower sample density."
	if raw_bytes>(MAX_RAW_BYTES if storage_root.is_empty() else MAX_STREAM_BYTES): return "Bake exceeds its expanded-data storage budget."
	var packed:=raw.compress(FileAccess.COMPRESSION_ZSTD); bytes+=packed.size()
	if (storage_root.is_empty() and bytes+resource_bytes>MAX_BYTES) or bytes>MAX_STREAM_BYTES: return "Bake exceeds its storage budget. Nothing was replaced."
	var chunk:={"first":count-pending.size(),"count":pending.size(),"raw_size":raw.size(),"sha256":digest(packed)}
	if storage_root.is_empty(): chunk.data=packed
	else:
		var path:=storage_root.path_join("chunk-%06d.bin"%chunks.size()); var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null: return "Cannot write a bake chunk; previous bake preserved."
		file.store_buffer(packed); file.flush(); var status:=file.get_error(); file.close(); owned_files.append(path)
		if status!=OK: return "Bake storage is full or unavailable."
		chunk.file=path
	chunks.append(chunk); pending.clear(); pending_bytes=0; return ""
func finish_stream() -> String:
	var result:=flush()
	if not result.is_empty(): return result
	complete=true
	if not storage_root.is_empty():
		var path:=storage_root.path_join("cache.res")
		if ResourceSaver.save(self,path)!=OK: complete=false; return "Cannot save bake manifest."
		owned_files.append(path)
	return ""
func abort_stream() -> void:
	# Only this fresh transaction's exact files are removed; never a user directory.
	for path: String in owned_files:
		if path.get_base_dir()==storage_root: DirAccess.remove_absolute(path)
	owned_files.clear()
	if not storage_root.is_empty(): DirAccess.remove_absolute(storage_root)
func packed_chunk(chunk: Dictionary) -> PackedByteArray:
	var data: PackedByteArray=chunk.get("data",PackedByteArray())
	if chunk.has("file"):
		var path:=str(chunk.file); var file:=FileAccess.open(path,FileAccess.READ)
		if file==null: error="Missing bake chunk: "+path; return PackedByteArray()
		if file.get_length()>MAX_CHUNK_RAW: error="Bake chunk is larger than the safety budget."; return PackedByteArray()
		data=file.get_buffer(file.get_length())
	if chunk.has("sha256") and digest(data)!=str(chunk.sha256): error="Bake chunk failed its integrity check."; return PackedByteArray()
	return data
func frame(index: int) -> Dictionary:
	error=""
	index=clampi(index,0,maxi(0,count-1)); var low:=0; var high:=chunks.size()-1; var chunk_index:=-1
	while low<=high:
		var middle: int=(low+high)/2; var candidate: Dictionary=chunks[middle]
		if index<int(candidate.first): high=middle-1
		elif index>=int(candidate.first)+int(candidate.count): low=middle+1
		else: chunk_index=middle; break
	if chunk_index<0: return {}
	if not decoded.has(chunk_index):
		var chunk: Dictionary=chunks[chunk_index]
		if int(chunk.raw_size)<0 or int(chunk.raw_size)>MAX_CHUNK_RAW: error="Bake chunk has an invalid expanded size."; return {}
		var packed:=packed_chunk(chunk)
		if packed.is_empty(): return {}
		var raw: PackedByteArray=packed.decompress(int(chunk.raw_size),FileAccess.COMPRESSION_ZSTD)
		var frames: Variant=bytes_to_var(raw)
		if not frames is Array: error="Bake chunk does not contain valid frame data."; return {}
		while decoded.size()>=2: decoded.erase(decoded.keys()[0])
		decoded[chunk_index]=frames
	return decode(decoded[chunk_index][index-int(chunks[chunk_index].first)])
