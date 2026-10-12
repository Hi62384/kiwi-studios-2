extends RefCounted
## Exemplar quilting: bounded candidate search, overlap matching, propagated
## source locations, and minimum-error seams. Runs entirely on a worker.
static func difference(a: Color,b: Color) -> float:
	return Vector4(a.r*a.a,a.g*a.a,a.b*a.a,a.a).distance_squared_to(Vector4(b.r*b.a,b.g*b.a,b.b*b.a,b.a))

static func inside_sample(point: Vector2,area: Rect2i,settings: Dictionary) -> bool:
	if not Rect2(area).has_point(point): return false
	match settings.get("sample_shape","rectangle"):
		"circle": return ((point-Rect2(area).get_center())/(Vector2(area.size)*.5)).length_squared()<=1
		"lasso":
			var points: PackedVector2Array=settings.get("sample_points",PackedVector2Array())
			return points.size()<3 or Geometry2D.is_point_in_polygon(point,points)
	return true

static func valid_patch(candidate: Vector2i,extent: Vector2i,area: Rect2i,settings: Dictionary) -> bool:
	if not area.encloses(Rect2i(candidate,extent)): return false
	# Testing all four corners and the center prevents a patch crossing the
	# circular/freeform source boundary; concave masks need interior samples.
	for y in [0,extent.y/2,extent.y-1]:
		for x in [0,extent.x/2,extent.x-1]:
			if not inside_sample(Vector2(candidate+Vector2i(x,y))+Vector2.ONE*.5,area,settings): return false
	return true

static func synthesize(destination: Image,source: Image,source_area: Rect2i,mask: Image,settings: Dictionary,origin: Vector2i=Vector2i.ZERO,excluded: Rect2i=Rect2i()) -> Image:
	var result:=destination.duplicate() as Image
	source_area=source_area.intersection(Rect2i(Vector2i.ZERO,source.get_size()))
	if source_area.size.x<2 or source_area.size.y<2: return result
	var patch:=clampi(int(settings.get("patch_size",16)),3,64)
	patch=mini(patch,mini(source_area.size.x,source_area.size.y))
	var overlap:=maxi(1,patch/4); var step:=maxi(1,patch-overlap)
	var quality:=clampi(int(settings.get("quality",1)),0,2)
	var candidate_count: int=[12,32,64][quality]
	var known:=PackedByteArray(); known.resize(result.get_width()*result.get_height())
	for y in result.get_height():
		for x in result.get_width():
			if mask.get_pixel(x,y).a<.01: known[y*result.get_width()+x]=1
	var chosen: Dictionary={}
	for y in range(0,result.get_height(),step):
		for x in range(0,result.get_width(),step):
			var cancelled: Callable=settings.get("cancelled",Callable())
			if cancelled.is_valid() and cancelled.call(): return destination
			var target:=Rect2i(x,y,mini(patch,result.get_width()-x),mini(patch,result.get_height()-y))
			var search:=source_area
			if excluded.has_area():
				var radius:=maxi(patch*maxi(1,int(settings.get("search_radius",3))),maxi(excluded.size.x,excluded.size.y)/2+patch)
				search=Rect2i(origin+target.position-Vector2i.ONE*radius,Vector2i.ONE*(radius*2+patch)).intersection(source_area)
			var rng:=RandomNumberGenerator.new(); rng.seed=hash([settings.get("seed",0),origin+target.position])
			var best:=source_area.position; var score:=INF; var valid:=false
			var candidates: Array[Vector2i]=[]
			if chosen.has(Vector2i(x-step,y)): candidates.append(Vector2i(chosen[Vector2i(x-step,y)])+Vector2i(step,0))
			if chosen.has(Vector2i(x,y-step)): candidates.append(Vector2i(chosen[Vector2i(x,y-step)])+Vector2i(0,step))
			for i in candidate_count:
				candidates.append(search.position+Vector2i(rng.randi_range(0,maxi(0,search.size.x-patch)),rng.randi_range(0,maxi(0,search.size.y-patch))))
			for candidate in candidates:
				if not valid_patch(candidate,Vector2i.ONE*patch,source_area,settings): continue
				if excluded.has_area() and Rect2i(candidate,Vector2i.ONE*patch).intersects(excluded):
					var exclusion: Image=settings.get("exclusion_mask")
					if exclusion==null: continue
					var intersection:=Rect2i(candidate-Vector2i(settings.get("exclusion_origin",Vector2i.ZERO)),Vector2i.ONE*patch).intersection(Rect2i(Vector2i.ZERO,exclusion.get_size()))
					if intersection.has_area() and exclusion.get_region(intersection).get_used_rect().has_area(): continue
				var error:=0.0; var samples:=0
				for row in range(0,target.size.y,2):
					for column in range(0,target.size.x,2):
						var p:=target.position+Vector2i(column,row)
						if known[p.y*result.get_width()+p.x]==0: continue
						var weight:=float(settings.get("edge_preservation",1)) if mask.get_pixelv(p).a<.01 else 1.0
						error+=difference(result.get_pixelv(p),source.get_pixelv(candidate+Vector2i(column,row)))*weight; samples+=1
				var cost:=error/maxi(1,samples)+rng.randf()*.002*float(settings.get("variation",.3))
				if cost<score: score=cost; best=candidate; valid=true
			if not valid: continue
			chosen[target.position]=best
			var sample:=source.get_region(Rect2i(best,target.size))
			var preservation:=float(settings.get("texture_preservation",1))
			if not is_equal_approx(preservation,1):
				var average:=preload("res://Workspaces/ImageWorkspace/image_healing.gd").mean(sample,Rect2i(Vector2i.ZERO,sample.get_size()))
				for row in sample.get_height():
					for column in sample.get_width(): sample.set_pixel(column,row,preload("res://Workspaces/ImageWorkspace/image_healing.gd").adapt(sample.get_pixel(column,row),average,average,preservation))
			var left:=seam(result,sample,target.position,mini(overlap,target.size.x),true) if x>0 else PackedInt32Array()
			var top:=seam(result,sample,target.position,mini(overlap,target.size.y),false) if y>0 else PackedInt32Array()
			for row in target.size.y:
				for column in target.size.x:
					var p:=target.position+Vector2i(column,row)
					if mask.get_pixelv(p).a<=0: continue
					if not left.is_empty() and column<left[row]: continue
					if not top.is_empty() and row<top[column]: continue
					var blend:=1.0
					if not left.is_empty() and column==left[row]: blend=.5
					if not top.is_empty() and row==top[column]: blend=.5
					result.set_pixelv(p,result.get_pixelv(p).lerp(sample.get_pixel(column,row),blend)); known[p.y*result.get_width()+p.x]=1
	return result

static func seam(destination: Image,patch: Image,origin: Vector2i,width: int,vertical: bool) -> PackedInt32Array:
	var height:=patch.get_height() if vertical else patch.get_width()
	var costs:=PackedFloat32Array(); costs.resize(width*height)
	var parents:=PackedInt32Array(); parents.resize(costs.size())
	for y in height:
		for x in width:
			var p:=Vector2i(x,y) if vertical else Vector2i(y,x)
			var error:=difference(destination.get_pixelv(origin+p),patch.get_pixelv(p))
			var previous:=x; var minimum:=0.0
			if y>0:
				minimum=INF
				for neighbor in range(maxi(0,x-1),mini(width,x+2)):
					if costs[(y-1)*width+neighbor]<minimum: minimum=costs[(y-1)*width+neighbor]; previous=neighbor
			costs[y*width+x]=error+minimum; parents[y*width+x]=previous
	var best:=0
	for x in width:
		if costs[(height-1)*width+x]<costs[(height-1)*width+best]: best=x
	var path:=PackedInt32Array(); path.resize(height)
	for y in range(height-1,-1,-1): path[y]=best; best=parents[y*width+best]
	return path
