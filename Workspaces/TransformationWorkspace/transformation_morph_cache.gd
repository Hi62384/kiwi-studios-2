class_name KiwiTransformationMorphCache
extends Node
signal prepared
var entries: Dictionary={}
var requests: Array[Dictionary]=[]
var worker: Thread
var active := ""
var analysis_count := 0
var preparation_usec := 0
var field_analysis_count := 0
var basis_cache: Dictionary={}
var active_basis := ""
func signature(a: KiwiTransformationState, b: KiwiTransformationState, key: KiwiTransformationKey) -> String:
	# Artwork uses copy-on-write textures. Moving, scaling, or changing opacity
	# must not invalidate image correspondence for an unchanged pair of images.
	return a.id+"/"+b.id+"/"+str(a.artwork.texture.get_instance_id())+"/"+str(b.artwork.texture.get_instance_id())+"/"+str(hash([key.points_a if key!=null else [],key.points_b if key!=null else [],key.settings() if key!=null else {}]))
func get_pair(a: KiwiTransformationState, b: KiwiTransformationState, key: KiwiTransformationKey) -> Dictionary:
	var id := signature(a,b,key)
	if entries.has(id): return entries[id]
	if active!=id and not requests.any(func(item: Dictionary): return item.id==id):
		# Analysis only needs a bounded copy. Never queue full-resolution canvases
		# while an artist drags correspondence points or scrubs many transitions.
		while requests.size()>=8: requests.pop_front()
		var high := key!=null and key.quality=="High"
		# Resource hashes are not a persistent identity (and can collide after
		# many short-lived image resources). Keep full, generation-aware IDs.
		var base_id := str(a.artwork.texture.get_instance_id())+"/"+str(b.artwork.texture.get_instance_id())+"/"+str(high)
		requests.append({"id":id,"base_id":base_id,"a":analysis_image(a.artwork.texture,192 if high else 128),"b":analysis_image(b.artwork.texture,192 if high else 128),"pa":key.points_a.duplicate() if key!=null else PackedVector2Array(),"pb":key.points_b.duplicate() if key!=null else PackedVector2Array(),"settings":key.settings() if key!=null else {}})
	return {}
static func analysis_image(texture: Texture2D, limit: int=128) -> Image:
	var source := texture.get_image()
	if source==null or source.is_empty(): return null
	var image := source.duplicate()
	var scale := minf(1.,float(limit)/maxi(image.get_width(),image.get_height()))
	if scale<1.: image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
	return image
func _process(_delta: float) -> void:
	if worker!=null:
		if worker.is_alive(): return
		var result: Dictionary=worker.wait_to_finish(); preparation_usec+=int(result.get("analysis_us",0))
		for field in ["field_a","field_b"]:
			if result.get(field) is Image: result[field]=ImageTexture.create_from_image(result[field])
		if result.has("basis"):
			result.basis.field_a=result.field_a; result.basis.field_b=result.field_b; basis_cache[active_basis]=result.basis; result.erase("basis")
			while basis_cache.size()>8: basis_cache.erase(basis_cache.keys()[0])
		entries[active]=result; worker=null; active=""; prepared.emit()
		while entries.size()>24: entries.erase(entries.keys()[0])
	if requests.is_empty(): return
	var task: Dictionary=requests.pop_front(); active=task.id; active_basis=task.base_id; worker=Thread.new(); analysis_count+=1
	var basis: Dictionary=basis_cache.get(active_basis,{})
	if basis.is_empty(): field_analysis_count+=1
	var error := worker.start(KiwiTransformationMorph.prepare.bind(task.a,task.b,task.pa,task.pb,task.settings,basis))
	if error!=OK: entries[active]={"valid":false,"empty_a":false,"empty_b":false,"reason":"Morph preparation unavailable: crossfade fallback."}; worker=null; active=""; prepared.emit()
func _exit_tree() -> void:
	if worker!=null: worker.wait_to_finish(); worker=null
