class_name KiwiMorphDeformation
extends RefCounted
## Paired constrained vertices, Delaunay candidate triangulations and analytic
## all-time triangle-area validation. Raster colors travel with paired UVs.
static func append_pair(a: Array[Vector2],b: Array[Vector2],p: Vector2,q: Vector2) -> void:
	for i in a.size():
		if a[i].distance_squared_to(p)<.000004 or b[i].distance_squared_to(q)<.000004: return
	a.append(p); b.append(q)
static func triangulate(a: PackedVector2Array,b: PackedVector2Array) -> Dictionary:
	var middle := PackedVector2Array()
	for i in a.size(): middle.append(a[i].lerp(b[i],.5))
	var best := {}; var score := INF
	for domain in [middle,a,b]:
		var indices := Geometry2D.triangulate_delaunay(domain)
		if indices.is_empty(): continue
		var quality := validate(a,b,indices)
		if quality.valid and quality.distortion<score: best={"valid":true,"uv_a":a,"uv_b":b,"indices":indices,"distortion":quality.distortion}; score=quality.distortion
	return best
static func validate(a: PackedVector2Array,b: PackedVector2Array,indices: PackedInt32Array) -> Dictionary:
	var distortion := 0.
	for i in range(0,indices.size(),3):
		var p := indices[i]; var q := indices[i+1]; var r := indices[i+2]
		var e := a[q]-a[p]; var f := a[r]-a[p]; var de := b[q]-b[p]-e; var df := b[r]-b[p]-f
		var c0 := e.cross(f); var c1 := de.cross(f)+e.cross(df); var c2 := de.cross(df)
		var middle := c0+c1*.5+c2*.25
		if absf(middle)<.000000001: return {"valid":false,"distortion":INF,"reason":"middle degenerate", "a":[a[p],a[q],a[r]],"b":[b[p],b[q],b[r]]}
		var sign := 1. if middle>0 else -1.; var minimum := minf(c0*sign,(c0+c1+c2)*sign)
		if absf(c2)>.00000001:
			var t := -c1/(2*c2)
			if t>0 and t<1: minimum=minf(minimum,(c0+c1*t+c2*t*t)*sign)
		# A corner can be collinear in just one endpoint (e.g. a closed eyelid).
		# Zero endpoint area is safe; any interior inversion is not. Rejecting
		# every such endpoint sliver prevents thin-to-open artwork morphing.
		if minimum<-.000000005: return {"valid":false,"distortion":INF,"reason":"inverted", "a":[a[p],a[q],a[r]],"b":[b[p],b[q],b[r]]}
		var scale_a := maxf(.000001,e.length()*f.length()); var edge_b := b[q]-b[p]; var edge_c := b[r]-b[p]; var scale_b := maxf(.000001,edge_b.length()*edge_c.length())
		# Bound slivers independently of overall squash/stretch, which is useful.
		if maxf(absf(c0)/scale_a,absf((c0+c1+c2))/scale_b)<.000001: return {"valid":false,"distortion":INF}
		distortion+=absf(log(maxf(.000001,absf(c0+c1+c2))/maxf(.000001,absf(c0))))
	return {"valid":true,"distortion":distortion/maxi(1,indices.size()/3)}
static func prepare(a: Dictionary,b: Dictionary,pins_a: PackedVector2Array,pins_b: PackedVector2Array,settings: Dictionary) -> Dictionary:
	var match_data := KiwiMorphAnalysis.match(a,b,80 if settings.get("quality","Fast")=="High" else 48,settings.get("alignment","Bounds"))
	var landmarks := KiwiMorphAnalysis.landmarks(a,b); var strength := float(settings.get("preservation",.8))
	if settings.get("strategy","")=="Shape Morph": strength*=.25
	elif settings.get("strategy","")=="Guided Morph" and not pins_a.is_empty(): strength*=.5
	for attempt in 2:
		var source: Array[Vector2]=[]; var target: Array[Vector2]=[]
		# Artist controls take priority over automatically proposed landmarks.
		for i in pins_a.size(): append_pair(source,target,pins_a[i],pins_b[i])
		for i in match_data.a.size(): append_pair(source,target,match_data.a[i],match_data.b[i])
		# Retain exact polygon tips, even when uniform arc samples miss them.
		for side in 2:
			var outline: PackedVector2Array=a.contour if side==0 else b.contour
			var sampled: PackedVector2Array=match_data.a if side==0 else match_data.b
			var paired: PackedVector2Array=match_data.b if side==0 else match_data.a
			for i in outline.size():
				var p := outline[i]; var incoming := (p-outline[(i+outline.size()-1)%outline.size()]).normalized(); var outgoing := (outline[(i+1)%outline.size()]-p).normalized()
				if minf(p.distance_to(outline[(i+outline.size()-1)%outline.size()]),p.distance_to(outline[(i+1)%outline.size()]))<.025: continue
				if incoming.dot(outgoing)>.6: continue
				var best := INF; var q := Vector2.ZERO
				for j in sampled.size():
					var next := (j+1)%sampled.size(); var near := Geometry2D.get_closest_point_to_segment(p,sampled[j],sampled[next]); var gap := p.distance_squared_to(near)
					if gap<best:
						best=gap; var t := sampled[j].distance_to(near)/maxf(.000001,sampled[j].distance_to(sampled[next])); q=paired[j].lerp(paired[next],t)
				if side==0: append_pair(source,target,p,q)
				else: append_pair(source,target,q,p)
		if attempt==0:
			for feature: Dictionary in landmarks:
				var normalized: Vector2=(feature.a-a.bounds.position)/a.bounds.size.max(Vector2.ONE*.001)
				var base: Vector2=b.bounds.position+normalized*b.bounds.size
				append_pair(source,target,feature.a,base.lerp(feature.b,strength))
		for point in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: append_pair(source,target,point,point)
		var result := triangulate(PackedVector2Array(source),PackedVector2Array(target))
		if not result.is_empty():
			result.method="Guided mesh" if not pins_a.is_empty() else "Contour + feature mesh"; result.landmarks=landmarks if attempt==0 else []; result.contour_a=match_data.a; result.contour_b=match_data.b; return result
	return {"valid":false,"reason":"Correspondence would invert or collapse triangles; using stable implicit topology."}
