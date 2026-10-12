class_name KiwiPixelSelectionEngine
extends Node
## Worker-owned analysis and segmentation; results enter the UI only on the
## main thread, with source/action generations rejecting stale work.

signal analyzed
signal proposed(mask: Image,kind: String,request: int)
var edges: KiwiPixelEdgeField
var objects: KiwiPixelObjectSegmenter
var source: Image
var domain: Rect2i
var _thread: Thread
var _job: Dictionary={}
var _pending: Dictionary={}
var _generation:=0
var _request:=0

func prepare(image: Image,area: Rect2i) -> void:
	_generation+=1; _request+=1; source=image; domain=area
	edges=null; objects=null
	_pending={"kind":"analyze","generation":_generation,"image":image,"domain":area}

func invalidate() -> void:
	_generation+=1; _request+=1; _pending.clear(); edges=null; objects=null; source=null

func cancel_request() -> void:
	_request+=1
	if _pending.get("kind","")!="analyze": _pending.clear()

func request(kind: String,seed: Vector2,threshold: float,width: float=1,coverage: Dictionary={}) -> int:
	_request+=1
	_pending={"kind":kind,"generation":_generation,"request":_request,"seed":seed,"threshold":threshold,"width":width,"coverage":coverage}
	return _request

func _process(_delta: float) -> void:
	if _thread!=null and not _thread.is_alive():
		var result: Dictionary=_thread.wait_to_finish(); _thread=null
		if _job.generation==_generation:
			if _job.kind=="analyze": edges=result.edges; objects=result.objects; analyzed.emit()
			else:
				if result.has("objects"): objects=result.objects
				if _job.request==_request: proposed.emit(result.get("mask"),_job.kind,_request)
	if _thread==null and (not _pending.is_empty() or (source!=null and edges==null)):
		if source==null or not domain.has_area(): _pending.clear(); return
		if edges==null:
			_job={"kind":"analyze","generation":_generation}
			if _pending.get("kind","")=="analyze": _pending.clear()
		else: _job=_pending; _pending={}
		_job.image=source; _job.domain=domain; _job.edges=edges; _job.objects=objects
		_thread=Thread.new(); _thread.start(_work.bind(_job))

func _work(job: Dictionary) -> Dictionary:
	if job.kind=="analyze":
		var field:=KiwiPixelEdgeField.new(); field.build(job.image,job.domain)
		return {"edges":field,"objects":null}
	if job.kind=="object":
		var segmenter: KiwiPixelObjectSegmenter=job.objects
		if segmenter==null: segmenter=KiwiPixelObjectSegmenter.new(); segmenter.build(job.image,job.domain)
		return {"mask":_finish_mask(segmenter.propose(job.seed,job.threshold),job),"objects":segmenter}
	var magnet:=KiwiPixelEdgeMagnet.new(); magnet.field=job.edges
	var path:=magnet.connected(job.seed,job.threshold)
	if path.is_empty(): return {}
	var mask:=Image.create(job.domain.size.x,job.domain.size.y,false,Image.FORMAT_RGBA8)
	for index in path.size(): path[index]-=Vector2(job.domain.position)
	KiwiPixelEdgeMagnet.paint_band(mask,path,job.width,Rect2i(Vector2i.ZERO,job.domain.size),Color.WHITE,false)
	return {"mask":_finish_mask(mask,job)}

func _finish_mask(mask: Image,job: Dictionary) -> Image:
	var coverage: Dictionary=job.get("coverage",{})
	if mask==null or coverage.is_empty(): return mask
	mask=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(mask,float(coverage.falloff))
	return preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend(coverage.base,mask,float(coverage.alpha),bool(coverage.subtract),coverage.origin)

func _exit_tree() -> void:
	if _thread!=null: _thread.wait_to_finish(); _thread=null
