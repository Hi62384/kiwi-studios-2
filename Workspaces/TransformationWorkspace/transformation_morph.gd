class_name KiwiTransformationMorph
extends RefCounted
const Analysis = preload("res://Workspaces/TransformationWorkspace/morph_analysis.gd")
const Deformation = preload("res://Workspaces/TransformationWorkspace/morph_deformation.gd")
const Field = preload("res://Workspaces/TransformationWorkspace/morph_distance_field.gd")
const GRID := 20
static func silhouette(image: Image) -> Dictionary: return Analysis.analyze(image)
static func axis_map(value: float,lo_a: float,hi_a: float,lo_b: float,hi_b: float) -> float:
	if value<lo_a: return value/maxf(.00001,lo_a)*lo_b
	if value>hi_a: return hi_b+(value-hi_a)/maxf(.00001,1.-hi_a)*(1.-hi_b)
	return lerpf(lo_b,hi_b,(value-lo_a)/maxf(.00001,hi_a-lo_a))
static func mapped(point: Vector2,a: PackedVector2Array,b: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO; var total := 0.
	for i in a.size():
		var gap := point.distance_squared_to(a[i])
		if gap<.00000001: return b[i]
		var weight := 1./maxf(.000000001,gap*gap); sum+=(b[i]-a[i])*weight; total+=weight
	return point+sum/maxf(.0000001,total)
static func identity() -> Dictionary:
	return {"valid":false,"empty_a":false,"empty_b":false,"reason":"Crossfade","uv_a":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),"uv_b":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),"indices":PackedInt32Array([0,1,2,0,2,3])}
static func prepare(image_a: Image,image_b: Image,pins_a: PackedVector2Array=PackedVector2Array(),pins_b: PackedVector2Array=PackedVector2Array(),settings: Dictionary={},basis: Dictionary={}) -> Dictionary:
	if image_a==null or image_b==null or image_a.is_empty() or image_b.is_empty():
		var missing := identity(); missing.reason="Missing source artwork: crossfade fallback."; return missing
	# Public callers get the same bounded preparation as the editor cache.
	image_a=bounded(image_a,192 if settings.get("quality","")=="High" else 128); image_b=bounded(image_b,192 if settings.get("quality","")=="High" else 128)
	var started := Time.get_ticks_usec(); var a: Dictionary=basis.analysis_a if not basis.is_empty() else Analysis.analyze(image_a); var b: Dictionary=basis.analysis_b if not basis.is_empty() else Analysis.analyze(image_b); var result := identity()
	result.empty_a=a.empty; result.empty_b=b.empty; result.method="Growth"; result.topology=false
	result.bounds_a=a.get("bounds",Rect2(Vector2.ZERO,Vector2.ONE)); result.bounds_b=b.get("bounds",Rect2(Vector2.ZERO,Vector2.ONE))
	if pins_a.size()!=pins_b.size(): result.reason="Invalid correction pair count."; return result
	for p in pins_a+pins_b:
		if not p.is_finite() or p.x<0 or p.y<0 or p.x>1 or p.y>1: result.reason="Invalid correspondence coordinate."; return result
	for i in pins_a.size():
		for j in i:
			if pins_a[i].distance_squared_to(pins_a[j])<.00000001 or pins_b[i].distance_squared_to(pins_b[j])<.00000001: result.reason="Conflicting correction pairs: crossfade fallback. Remove duplicate markers."; return result
	if not a.empty and not b.empty:
		if a.regions==1 and b.regions==1 and a.holes==0 and b.holes==0 and a.valid and b.valid:
			var mesh := Deformation.prepare(a,b,pins_a,pins_b,settings)
			if mesh.valid: result.merge(mesh,true)
			else: result.reason=mesh.reason
		if not result.valid:
			result.topology=true; result.method="Implicit topology"; result.valid=true
			if result.reason=="Crossfade": result.reason="Signed-distance topology: splitting, merging or holes."
			if settings.get("alignment","Bounds")=="Bounds" and a.valid and b.valid:
				result.uv_a=PackedVector2Array(); result.uv_b=PackedVector2Array(); result.indices=PackedInt32Array()
				for y in GRID+1:
					for x in GRID+1:
						var uv := Vector2(x,y)/GRID; result.uv_a.append(uv); result.uv_b.append(Vector2(axis_map(uv.x,a.bounds.position.x,a.bounds.end.x,b.bounds.position.x,b.bounds.end.x),axis_map(uv.y,a.bounds.position.y,a.bounds.end.y,b.bounds.position.y,b.bounds.end.y)))
				for y in GRID:
					for x in GRID:
						var i := y*(GRID+1)+x; result.indices.append_array(PackedInt32Array([i,i+1,i+GRID+2,i,i+GRID+2,i+GRID+1]))
	else: result.reason="Empty state: geometric growth / reveal."
	result.field_a=basis.field_a if not basis.is_empty() else Field.build(image_a,a,b.palette); result.field_b=basis.field_b if not basis.is_empty() else Field.build(image_b,b,a.palette)
	result.basis={"analysis_a":a,"analysis_b":b,"field_a":result.field_a,"field_b":result.field_b}
	result.regions_a=a.regions; result.regions_b=b.regions; result.holes_a=a.holes; result.holes_b=b.holes
	result.analysis_us=Time.get_ticks_usec()-started
	return result
static func bounded(image: Image,limit: int) -> Image:
	if maxi(image.get_width(),image.get_height())<=limit: return image
	var result := image.duplicate() as Image; var scale := float(limit)/maxi(image.get_width(),image.get_height()); result.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_BILINEAR); return result
