extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,title: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(title)
	else: print("PASS ",title)
func run() -> void:
	var cache:=KiwiPhysicsBakeCache.new()
	check(cache.begin_stream("user://bakes").is_empty(),"Stream opens a fresh owned transaction")
	var mesh:=BoxMesh.new()
	for i in 97:
		check(cache.append({"actor":{"pose":Transform3D(Basis.IDENTITY,Vector3(i,0,0)),"mesh":mesh}}).is_empty(),"Append frame %d"%i)
	check(cache.finish_stream().is_empty() and cache.complete,"Manifest commits only after chunks finish")
	check(cache.chunks.size()==4 and cache.resources.size()==1,"Resources intern once across streamed chunks")
	var loaded:=ResourceLoader.load(cache.storage_root.path_join("cache.res"),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiPhysicsBakeCache
	check(loaded!=null and loaded.frame(96).actor.pose.origin.x==96,"Reload seeks last external chunk")
	check(loaded.frame(0).actor.mesh is BoxMesh and loaded.decoded.size()<=2,"External seeks restore resources within bounded decoded cache")
	var chunk: String=cache.chunks[0].file
	var file:=FileAccess.open(chunk,FileAccess.WRITE); file.store_buffer(PackedByteArray([1,2,3])); file.close(); loaded.decoded.clear()
	check(loaded.frame(0).is_empty() and loaded.error.contains("integrity"),"Corrupt chunks fail safely with actionable status")
	DirAccess.remove_absolute(chunk); loaded.error=""
	check(loaded.frame(0).is_empty() and loaded.error.contains("Missing"),"Missing external chunks fail safely")
	var root_path:=cache.storage_root; cache.abort_stream()
	check(not DirAccess.dir_exists_absolute(root_path),"Rollback removes only transaction-owned files")
	var embedded:=KiwiPhysicsBakeCache.new(); embedded.append({"x":42}); check(embedded.finish_stream().is_empty() and embedded.frame(0).x==42,"Embedded caches retain compatibility")
	var adaptive:=KiwiPhysicsBakeCache.new(); var grid:=PackedFloat32Array(); grid.resize(350000); grid.fill(.25)
	for i in 15: adaptive.append({"frame":i,"fog_density":grid})
	check(adaptive.finish_stream().is_empty() and adaptive.chunks.size()==2 and int(adaptive.chunks[1].first)<32,"Large volumetric frames split before the 16 MiB chunk limit")
	check(adaptive.frame(14).frame==14 and adaptive.frame(0).fog_density.size()==350000,"Adaptive chunk lookup seeks both sides of variable frame boundaries")
	print("BAKE STORAGE: %d checks, %d failures"%[checks,failures]); quit(failures)
