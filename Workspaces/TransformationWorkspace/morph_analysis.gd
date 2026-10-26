class_name KiwiMorphAnalysis
extends RefCounted
## Bounded, worker-safe analysis in component-local UV coordinates.
static func analyze(image: Image) -> Dictionary:
	if image==null or image.is_empty(): return {"empty":true,"regions":0,"holes":0,"palette":[]}
	var size := image.get_size(); var data: Image=image.duplicate(); data.convert(Image.FORMAT_RGBA8)
	var pixels := data.get_data(); var mask := PackedByteArray(); mask.resize(size.x*size.y)
	var bins := {}; var mass := 0.; var center := Vector2.ZERO; var max_alpha := 0.
	for i in mask.size(): max_alpha=maxf(max_alpha,float(pixels[i*4+3])/255.)
	if max_alpha<.003: return {"empty":true,"regions":0,"holes":0,"palette":[]}
	var threshold := minf(.12,max_alpha*.5)
	for i in mask.size():
		var index := i*4; var alpha := float(pixels[index+3])/255.; mask[i]=1 if alpha>=threshold else 0
		if alpha<threshold: continue
		var uv := (Vector2(i%size.x,i/size.x)+Vector2.ONE*.5)/Vector2(size)
		mass+=alpha; center+=uv*alpha
		var r := int(pixels[index]); var g := int(pixels[index+1]); var b := int(pixels[index+2]); var id := (r>>5)*64+(g>>5)*8+(b>>5)
		if not bins.has(id): bins[id]={"mass":0.,"point":Vector2.ZERO,"rgb":Vector3.ZERO}
		var bin: Dictionary=bins[id]; bin.mass+=alpha; bin.point+=uv*alpha; bin.rgb+=Vector3(r,g,b)/255.*alpha
	center/=maxf(.00001,mass)
	var palette: Array=[]
	for bin: Dictionary in bins.values():
		if bin.mass<maxf(1.,mass*.0005): continue
		palette.append({"point":bin.point/bin.mass,"color":bin.rgb/bin.mass,"mass":bin.mass/mass})
	palette.sort_custom(func(a: Dictionary,b: Dictionary): return a.mass>b.mass)
	if palette.size()>32: palette.resize(32)
	var bitmap := BitMap.new(); bitmap.create_from_image_alpha(data,threshold)
	var polygons := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,size),1.25)
	var contour := PackedVector2Array(); var area := 0.
	for polygon: PackedVector2Array in polygons:
		var candidate := absf(signed_area(polygon))
		if candidate>area: area=candidate; contour=polygon.duplicate()
	for i in contour.size(): contour[i]=(contour[i]/Vector2(size)).clamp(Vector2.ZERO,Vector2.ONE)
	if signed_area(contour)<0: contour.reverse()
	var topology := regions(mask,size)
	var bounds := Rect2(center,Vector2.ZERO)
	if not contour.is_empty():
		bounds=Rect2(contour[0],Vector2.ZERO)
		for p in contour: bounds=bounds.expand(p)
	return {"empty":false,"valid":contour.size()>=3,"contour":contour,"bounds":bounds,"center":center,"palette":palette,"mask":mask,"size":size,"regions":topology.regions,"holes":topology.holes}
static func signed_area(points: PackedVector2Array) -> float:
	var area := 0.
	for i in points.size(): area+=points[i].cross(points[(i+1)%points.size()])
	return area*.5
static func regions(mask: PackedByteArray, size: Vector2i) -> Dictionary:
	var visited := PackedByteArray(); visited.resize(mask.size()); var counts := {"regions":0,"holes":0}
	for start in mask.size():
		if visited[start]!=0: continue
		var ink := mask[start]; var queue := PackedInt32Array([start]); visited[start]=1; var cursor := 0; var border := false
		while cursor<queue.size():
			var i := queue[cursor]; cursor+=1; var x := i%size.x; var y := i/size.x
			border=border or x==0 or y==0 or x==size.x-1 or y==size.y-1
			for next in [i-1 if x>0 else -1,i+1 if x<size.x-1 else -1,i-size.x if y>0 else -1,i+size.x if y<size.y-1 else -1]:
				if next>=0 and visited[next]==0 and mask[next]==ink: visited[next]=1; queue.append(next)
		if ink!=0: counts.regions+=1
		elif not border: counts.holes+=1
	return counts
static func resample(points: PackedVector2Array, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size()<3: return result
	var lengths := PackedFloat32Array([0.]); var total := 0.
	for i in points.size(): total+=points[i].distance_to(points[(i+1)%points.size()]); lengths.append(total)
	var segment := 0
	for i in count:
		var distance := total*i/count
		while segment+1<points.size() and lengths[segment+1]<distance: segment+=1
		result.append(points[segment].lerp(points[(segment+1)%points.size()],(distance-lengths[segment])/maxf(.000001,lengths[segment+1]-lengths[segment])))
	return result
static func match(a: Dictionary, b: Dictionary, count: int, alignment: String="Bounds") -> Dictionary:
	var source := resample(a.contour,count); var target := resample(b.contour,count); var best := INF; var phase := 0
	for shift in count:
		var score := 0.
		for i in count:
			var j := (i+shift)%count; var p: Vector2=source[i]; var q: Vector2=target[j]
			if alignment=="Bounds": p=(p-a.bounds.position)/a.bounds.size.max(Vector2.ONE*.001); q=(q-b.bounds.position)/b.bounds.size.max(Vector2.ONE*.001)
			var curvature_a := (source[(i+count-2)%count]-source[i]).normalized().dot((source[(i+2)%count]-source[i]).normalized())
			var curvature_b := (target[(j+count-2)%count]-target[j]).normalized().dot((target[(j+2)%count]-target[j]).normalized())
			score+=p.distance_squared_to(q)+.06*absf(curvature_a-curvature_b)
		if score<best: best=score; phase=shift
	var paired := PackedVector2Array()
	for i in count: paired.append(target[(i+phase)%count])
	return {"a":source,"b":paired,"cost":best/count,"phase":phase}
static func landmarks(a: Dictionary,b: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var used := {}
	for feature: Dictionary in a.palette:
		var best := .025; var chosen := -1
		for i in b.palette.size():
			if used.has(i): continue
			var other: Dictionary=b.palette[i]; var color_gap: float=feature.color.distance_squared_to(other.color)
			if color_gap>best or minf(feature.mass,other.mass)/maxf(feature.mass,other.mass)<.025: continue
			best=color_gap; chosen=i
		if chosen>=0:
			used[chosen]=true; result.append({"a":feature.point,"b":b.palette[chosen].point,"color":feature.color})
	return result
