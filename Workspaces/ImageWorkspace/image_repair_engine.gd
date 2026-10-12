extends Node
## Background-only image processing. Main thread owns scene nodes and textures;
## generations reject results after cancellation, undo or document changes.
signal preview(result: Dictionary)
signal idle
var _thread: Thread
var _pending: Dictionary={}
var _job: Dictionary={}
var _generation:=0
var _sequence:=0

func cancel() -> void: _generation+=1; _pending.clear()
func submit(job: Dictionary) -> int:
	_sequence+=1; _pending=job.duplicate(); _pending.generation=_generation; _pending.sequence=_sequence
	return _sequence
func busy() -> bool: return _thread!=null or not _pending.is_empty()

func _process(_delta: float) -> void:
	if _thread!=null and not _thread.is_alive():
		var result: Dictionary=_thread.wait_to_finish(); _thread=null
		if _job.generation==_generation:
			result.sequence=_job.sequence; preview.emit(result)
	if _thread==null and not _pending.is_empty():
		_job=_pending; _pending={}; _thread=Thread.new(); _thread.start(_work.bind(_job))
	elif _thread==null: idle.emit()

func _work(job: Dictionary) -> Dictionary:
	if job.kind=="generate":
		return {"image":preload("res://Workspaces/ImageWorkspace/image_procedural_texture.gd").generate(job.recipe,job.size,func(): return job.generation!=_generation),"kind":"generate","target":job.get("target","")}
	var original: Image=job.original; var sample: Image=job.sample
	var settings: Dictionary=job.settings; var area: Rect2i=job.area
	settings=settings.duplicate(); settings.cancelled=func(): return job.generation!=_generation
	var size:=area.size; var mask:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	var scattered: bool=settings.get("application","continuous")=="scatter"
	var stamped: bool=settings.get("application","continuous") in ["stamp","scatter"]
	var points: PackedVector2Array=job.points.duplicate(); var angles:=PackedFloat32Array(); var scales:=PackedFloat32Array(); var buckets: Dictionary={}
	if stamped:
		for index in points.size():
			var rng:=RandomNumberGenerator.new(); rng.seed=hash([points[index],settings.get("seed",0)])
			if scattered: points[index]+=Vector2(rng.randf_range(-1,1),rng.randf_range(-1,1))*float(settings.size)*float(settings.get("jitter",.25))
			var angle:=deg_to_rad(float(settings.get("rotation",0))+rng.randf_range(-1,1)*float(settings.get("random_rotation",0)))
			if settings.get("follow_direction",false) and index>0: angle+=(points[index]-points[index-1]).angle()
			angles.append(angle); scales.append(maxf(.1,1+rng.randf_range(-1,1)*float(settings.get("random_scale",0))))
			var bucket:=Vector2i((points[index]/float(settings.size)).floor())
			for y in range(-1,2):
				for x in range(-1,2):
					var key:=bucket+Vector2i(x,y)
					if not buckets.has(key): buckets[key]=[]
					buckets[key].append(index)
	var stamp:=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").stamp(float(settings.size),1-float(settings.hardness))
	if stamped: stamp.fill(Color.WHITE)
	for i in job.points.size():
		var point: Vector2=points[i]
		var dab: Image=stamp
		if settings.get("pressure",false):
			var pressures: PackedFloat32Array=settings.get("pressures",PackedFloat32Array())
			var pressure:=pressures[i] if i<pressures.size() else 1.0
			dab=stamp.duplicate(); var diameter:=maxi(1,roundi(float(settings.size)*pressure)); dab.resize(diameter,diameter,Image.INTERPOLATE_BILINEAR)
		mask.blend_rect(dab,Rect2i(Vector2i.ZERO,dab.get_size()),Vector2i(point)-area.position-dab.get_size()/2)
	if job.get("fill",false): mask.fill(Color.WHITE)
	if job.get("fill",false) and job.get("selection")!=null and float(settings.get("boundary_feather",0))>0:
		# Feathering is applied to the selection below, not the rectangular job.
		job=job.duplicate(); job.selection=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(job.selection,float(settings.boundary_feather))
	if job.get("editable_texture",false) and job.get("selection")==null and job.get("layer_mask")==null and not settings.get("clip_alpha",false):
		# Native compositing handles the common unmasked path. Only alpha scaling
		# visits bytes; no Color objects, synthesis or per-pixel coordinate mapping.
		var amount:=float(settings.get("strength",1))*float(settings.get("opacity",1))
		if not is_equal_approx(amount,1):
			var bytes:=mask.get_data()
			for offset in range(3,bytes.size(),4): bytes[offset]=roundi(bytes[offset]*amount)
			mask=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)
		var coverage: Image=job.prior_coverage.get_region(area)
		coverage.blend_rect(mask,Rect2i(Vector2i.ZERO,size),Vector2i.ZERO)
		return {"area":area,"kind":job.kind,"coverage":coverage}
	var destination:=original.get_region(area); var reconstructed:=destination.duplicate() as Image
	var source_area: Rect2i=job.source_area
	var mode: String=job.kind
	if job.get("editable_texture",false):
		pass # GPU material evaluation needs only painted coverage, never CPU RGB synthesis.
	elif mode in ["pattern_heal","patch"] or (mode in ["pattern_fill","procedural"] and settings.get("behavior","")=="synthesis"):
		var excluded: Rect2i=area if job.get("automatic",false) else Rect2i()
		var matching_mask:=job.local_selection.get_region(area) as Image if job.get("local_selection")!=null else mask
		if job.get("automatic",false): settings.exclusion_mask=matching_mask; settings.exclusion_origin=area.position
		reconstructed=preload("res://Workspaces/ImageWorkspace/image_texture_synthesis.gd").synthesize(destination,sample,source_area,matching_mask,settings,area.position,excluded)
	elif mode=="spot":
		# Long strokes are repaired in local patches, never as one enormous
		# rectangle that would require a same-sized clean source.
		var tile:=maxi(8,mini(32,roundi(float(settings.size))))
		for y in range(area.position.y,area.end.y,tile):
			for x in range(area.position.x,area.end.x,tile):
				if job.generation!=_generation: return {"kind":mode}
				var piece:=Rect2i(x,y,mini(tile,area.end.x-x),mini(tile,area.end.y-y))
				var patch:=preload("res://Workspaces/ImageWorkspace/image_healing.gd").spot_patch(original,piece,settings,area)
				reconstructed.blit_rect(patch,Rect2i(Vector2i.ZERO,patch.get_size()),piece.position-area.position)
	else:
		var source_mean:=preload("res://Workspaces/ImageWorkspace/image_healing.gd").mean(sample,source_area)
		var target_mean:=preload("res://Workspaces/ImageWorkspace/image_healing.gd").mean(original,area.grow(maxi(4,maxi(size.x,size.y)/2)),area)
		for y in size.y:
			if job.generation!=_generation: return {"kind":mode}
			for x in size.x:
				var p:=Vector2(area.position+Vector2i(x,y)); var color:=Color.TRANSPARENT
				if mode in ["pattern_fill","procedural"]:
					if stamped and not job.get("fill",false):
						var best:=-1; var distance:=INF
						for index in buckets.get(Vector2i((p/float(settings.size)).floor()),[]):
							var next:=p.distance_squared_to(points[index])
							if next<distance: distance=next; best=index
						if best>=0:
							var at:=(p-points[best]).rotated(-angles[best])/maxf(1,float(settings.get("stamp_extent",settings.size))*scales[best])+Vector2.ONE*.5
							if Rect2(0,0,1,1).has_point(at): color=sample.get_pixelv((Vector2i(at*Vector2(sample.get_size()))).clamp(Vector2i.ZERO,sample.get_size()-Vector2i.ONE))
					else: color=preload("res://Workspaces/ImageWorkspace/image_pattern_fill.gd").sample(sample,source_area,p,settings)
				else:
					var delta: Vector2=(p-Vector2(job.destination_anchor)).rotated(-deg_to_rad(float(settings.get("rotation",0))))/maxf(.01,float(settings.get("scale",1)))
					var basis: Transform2D=job.get("sample_basis",Transform2D.IDENTITY)
					var sample_delta:=basis.basis_xform(delta)
					if settings.get("sample_mode","current")!="current" and job.get("reference")!=null:
						var sampled_layer: KiwiImageLayer=job.reference; var sampled_frame: Transform2D=job.frame
						var anchor: Vector2=job.destination_anchor
						sample_delta=sampled_frame.basis_xform(sampled_layer.project_point((anchor+delta)/Vector2(original.get_size())*sampled_layer.dimensions)-sampled_layer.project_point(anchor/Vector2(original.get_size())*sampled_layer.dimensions))
					var source_point:=Vector2(job.source_anchor)+Vector2(settings.get("offset",Vector2.ZERO))+sample_delta
					if not Rect2(Vector2.ZERO,Vector2(sample.get_size())).has_point(source_point):
						mask.set_pixel(x,y,Color.TRANSPARENT); continue
					color=sample.get_pixelv(Vector2i(source_point))
					if mode=="heal" and settings.get("healing_blend","texture")=="texture": color=preload("res://Workspaces/ImageWorkspace/image_healing.gd").adapt(color,source_mean,target_mean,float(settings.get("texture_preservation",1)))
				reconstructed.set_pixel(x,y,color)
	var output:=destination.duplicate() as Image
	var material_coverage:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	var selection: Image=job.get("selection")
	var frame: Transform2D=job.get("frame",Transform2D.IDENTITY)
	var reference: KiwiImageLayer=job.get("reference")
	var selection_inverse: Transform2D=job.get("selection_inverse",Transform2D.IDENTITY)
	var selection_reference: KiwiImageLayer=job.get("selection_reference")
	var selection_world: Transform2D=job.get("selection_world",Transform2D.IDENTITY)
	for y in size.y:
		if job.generation!=_generation: return {"kind":mode}
		for x in size.x:
			var coverage:=mask.get_pixel(x,y).a*float(settings.get("strength",1))*float(settings.get("opacity",1))
			var p:=Vector2(area.position+Vector2i(x,y))+Vector2.ONE*.5
			if job.get("local_selection")!=null:
				coverage*=job.local_selection.get_pixelv(Vector2i(p)).a
			elif selection!=null and settings.get("selection_only",true):
				var world: Vector2=frame*reference.project_point(p/Vector2(original.get_size())*reference.dimensions) if reference!=null else frame*p
				var at: Vector2=selection_inverse*world
				if selection_reference!=null: at=selection_world*selection_reference.project_point(reference.unproject_point(frame.affine_inverse()*world)/reference.dimensions*selection_reference.dimensions)
				var pixel:=Vector2i(at.floor()); coverage*=selection.get_pixelv(pixel).a if Rect2i(Vector2i.ZERO,selection.get_size()).has_point(pixel) else 0.0
			if settings.get("clip_alpha",false): coverage*=original.get_pixelv(Vector2i(p)).a
			var layer_mask: Image=job.get("layer_mask")
			if layer_mask!=null:
				var uv:=p/Vector2(original.get_size()); coverage*=layer_mask.get_pixelv(Vector2i(uv*Vector2(layer_mask.get_size())).clamp(Vector2i.ZERO,layer_mask.get_size()-Vector2i.ONE)).r
			var desired:=reconstructed.get_pixel(x,y)
			if job.get("editable_texture",false):
				var prior: Image=job.prior_coverage; var old:=prior.get_pixelv(area.position+Vector2i(x,y)).a
				material_coverage.set_pixel(x,y,Color(1,1,1,old+(1-old)*clampf(coverage,0,1)))
				continue
			if settings.has("material_blending"):
				var original_color:=destination.get_pixel(x,y)
				match settings.material_blending:
					"overlay":
						for channel in 3: desired[channel]=2*original_color[channel]*desired[channel] if original_color[channel]<.5 else 1-2*(1-original_color[channel])*(1-desired[channel])
					"colorize":
						var ratio:=original_color.get_luminance()/maxf(.01,desired.get_luminance()); desired.r*=ratio; desired.g*=ratio; desired.b*=ratio
					"detail":
						var gain:=.65+desired.get_luminance()*.7; desired.r=original_color.r*gain; desired.g=original_color.g*gain; desired.b=original_color.b*gain
			if mode in ["pattern_fill","procedural"] and desired.a<1 and not settings.get("new_layer",false):
				var old:=destination.get_pixel(x,y); var alpha:=desired.a+old.a*(1-desired.a)
				desired=Color((desired.r*desired.a+old.r*old.a*(1-desired.a))/maxf(.00001,alpha),(desired.g*desired.a+old.g*old.a*(1-desired.a))/maxf(.00001,alpha),(desired.b*desired.a+old.b*old.a*(1-desired.a))/maxf(.00001,alpha),alpha)
			if settings.get("new_layer",false): output.set_pixel(x,y,Color(desired.r,desired.g,desired.b,desired.a*clampf(coverage,0,1)))
			else: output.set_pixel(x,y,destination.get_pixel(x,y).lerp(desired,clampf(coverage,0,1)))
	return {"image":output,"area":area,"kind":mode,"coverage":material_coverage}

func _exit_tree() -> void:
	cancel()
	if _thread!=null: _thread.wait_to_finish(); _thread=null
