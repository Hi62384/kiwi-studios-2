extends SceneTree
## Path-only checks run without a GPU or any painting/UI dependencies.
var failures:=0

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: run.call_deferred()

func fit(path: PackedVector2Array,amount: float,rate: float=120.0) -> KiwiStrokeCorrector:
	var corrector:=KiwiStrokeCorrector.new(); corrector.begin(path[0],amount,28,0)
	for i in range(1,path.size()):
		corrector.add(path[i],float(i)/rate); corrector.update()
	corrector.update(); return corrector

func line_error(corrector: KiwiStrokeCorrector) -> float:
	var error:=0.0
	for i in range(12,corrector.knots.size()-12): error+=corrector.knots[i].y*corrector.knots[i].y
	return sqrt(error/maxi(1,corrector.knots.size()-24))

func circle_error(corrector: KiwiStrokeCorrector,radius: float) -> float:
	var error:=0.0
	for i in range(12,corrector.knots.size()-12): error+=absf(corrector.knots[i].length()-radius)
	return error/maxi(1,corrector.knots.size()-24)

func run() -> void:
	var line:=PackedVector2Array()
	for i in 250: line.append(Vector2(i*1.2,sin(i*1.9)*2.0))
	var raw:=fit(line,0.0); var light:=fit(line,.25); var medium:=fit(line,.5); var strong:=fit(line,1.0)
	print("Line RMS raw/light/medium/strong: ",line_error(raw)," / ",line_error(light)," / ",line_error(medium)," / ",line_error(strong))
	check(line_error(strong)<line_error(raw)*.15,"Maximum correction removes most straight-line jitter")
	check(line_error(light)>line_error(medium) and line_error(medium)>line_error(strong),"Strength produces progressively stronger correction")
	check(strong.knots[0]==line[0] and strong.knots[-1].is_equal_approx(line[-1]),"Start and end locations are preserved")
	var arc:=PackedVector2Array()
	for i in 240:
		var angle:=float(i)/239*PI
		arc.append(Vector2(cos(angle),sin(angle))*(90+sin(i*1.7)*1.8))
	var smooth_arc:=fit(arc,1)
	print("Arc radial error raw/strong: ",circle_error(fit(arc,0),90)," / ",circle_error(smooth_arc,90))
	check(circle_error(smooth_arc,90)<circle_error(fit(arc,0),90)*.15,"Arc correction removes bumps without forcing a different radius")
	var broad:=PackedVector2Array()
	for i in 500: broad.append(Vector2(i,sin(i*TAU/22.0)*3+sin(i*1.7)*.6))
	var thin:=KiwiStrokeCorrector.new(); thin.begin(broad[0],1,2,0)
	for i in range(1,broad.size()): thin.add(broad[i],i/120.0); thin.update()
	print("Broad wobble RMS raw/thin corrected: ",line_error(fit(broad,0))," / ",line_error(thin))
	var corner_count:=0
	for corner_value in thin.corners: if corner_value!=0: corner_count+=1
	print("Broad wobble corner flags: ",corner_count)
	check(line_error(thin)<line_error(fit(broad,0))*.25,"Thin brushes correct broad hand wobble rather than only subpixel jitter")
	var larger:=PackedVector2Array()
	for i in 1001: larger.append(Vector2(i,sin(i*TAU/160.0)*15))
	var normal_scale:=KiwiStrokeCorrector.new(); var large_scale:=KiwiStrokeCorrector.new()
	normal_scale.begin(larger[0],1,3,0,1); large_scale.begin(larger[0],1,3,0,4)
	for i in range(1,larger.size()):
		normal_scale.add(larger[i],i/120.0); large_scale.add(larger[i],i/120.0)
		if i%4==0: normal_scale.update(); large_scale.update()
	normal_scale.update(); large_scale.update()
	check(line_error(large_scale)<line_error(normal_scale)*.4,"Increasing correction scale smooths larger physical features")
	var gapped:=PackedVector2Array()
	var vertices:=PackedVector2Array([Vector2.ZERO,Vector2(400,0),Vector2(400,400),Vector2(0,400),Vector2(0,60)])
	for edge in 4:
		for i in 81: gapped.append(vertices[edge].lerp(vertices[edge+1],i/80.0))
	var small_gap:=KiwiStrokeCorrector.new(); var wide_gap:=KiwiStrokeCorrector.new()
	small_gap.begin(gapped[0],1,3,0,1); wide_gap.begin(gapped[0],1,3,0,4)
	var small_closed:=false; var wide_closed:=PackedVector2Array()
	for i in range(1,gapped.size()):
		small_gap.add(gapped[i],i/120.0); wide_gap.add(gapped[i],i/120.0)
		var small_patch:=small_gap.update(); var wide_patch:=wide_gap.update()
		if small_patch.has("replace"): small_closed=true
		if wide_patch.has("replace"): wide_closed=wide_patch.replace
	check(not small_closed and wide_closed.is_empty(),"Large gaps stay open at both normal and large correction scales")
	for scale in [.1,1.0,4.0,16.0]:
		for brush_width in [3.0,500.0]:
			var closer:=KiwiStrokeCorrector.new(); closer.begin(gapped[0],1,brush_width,0,scale)
			for i in range(1,gapped.size()): closer.add(gapped[i],i/120.0)
			closer.add(Vector2(0,17),3)
			check(not closer.update().has("replace"),"A 17px gap remains open at scale %s with brush width %s" % [scale,brush_width])
			closer.add(Vector2(0,16),3.01)
			var joined:=closer.update()
			check(joined.has("replace"),"A 16px gap closes at scale %s with brush width %s" % [scale,brush_width])
			if joined.has("replace"):
				check(joined.replace[0].is_equal_approx(joined.replace[-1]),"Corrected loops close with an exact seam")
				var span:=mini(clampi(ceili(8/maxf(.1,closer.spacing)),1,12),(closer.knots.size()-1)/5)
				var length:=closer.knots[span].distance_to(closer.knots[closer.knots.size()-1-span])
				var count:=clampi(ceili(length/.5),8,128)
				for point in joined.replace.slice(joined.replace.size()-count):
					check(closer._raw_bounds.grow(.001).has_point(point),"Gap connector stays within the drawn shape instead of bulging outward")
	var corner:=PackedVector2Array()
	for i in 51: corner.append(Vector2(i*2,0))
	for i in range(1,51): corner.append(Vector2(100,i*2))
	var sharp:=fit(corner,1)
	var nearest:=INF
	for point in sharp.knots: nearest=minf(nearest,point.distance_to(Vector2(100,0)))
	check(nearest<1.0,"Deliberate right-angle corners stay recognizable")
	var detail:=PackedVector2Array()
	for i in 81: detail.append(Vector2(cos(i/80.0*PI),sin(i/80.0*PI))*5.0)
	var hook:=fit(detail,1); var smallest:=INF
	for point in hook.knots: smallest=minf(smallest,point.length())
	check(smallest>4.0,"Tight intentional curved details retain their shape at maximum strength")
	var click:=KiwiStrokeCorrector.new(); click.begin(Vector2(7,9),1,20)
	check(click.update().tail==PackedVector2Array([Vector2(7,9)]),"Single clicks produce an anchored point")
	click.add(Vector2(7.2,9.1),.01)
	check(click.update().tail[-1].is_equal_approx(Vector2(7.2,9.1)),"Sub-spacing strokes preserve their exact endpoint")
	var fast:=fit(PackedVector2Array([Vector2.ZERO,Vector2(1000,0),Vector2(2000,0)]),1,1000)
	check(line_error(fast)<.001,"Fast movements preserve a straight path without large deviations")
	var sparse:=PackedVector2Array(); var dense:=PackedVector2Array()
	for i in 101: sparse.append(Vector2(i*2,0))
	for i in 401: dense.append(Vector2(i*.5,0))
	var sparse_knots:=fit(sparse,1).knots; var dense_knots:=fit(dense,1).knots
	var equivalent:=sparse_knots.size()==dense_knots.size()
	var difference:=0.0
	if equivalent:
		for i in sparse_knots.size(): difference=maxf(difference,sparse_knots[i].distance_to(dense_knots[i])); equivalent=equivalent and sparse_knots[i].distance_to(dense_knots[i])<.001
	print("Polling equivalence: ",sparse_knots.size()," / ",dense_knots.size(),"; largest delta ",difference)
	check(equivalent,"Arc-length resampling is independent of input polling density")
	var long_path:=KiwiStrokeCorrector.new(); long_path.begin(Vector2.ZERO,.75,28)
	var started:=Time.get_ticks_usec(); var maximum_tail:=0; var maximum_update:=0.0
	for i in range(1,2501):
		var update_started:=Time.get_ticks_usec()
		long_path.add(Vector2(i,sin(i*.03)*25+sin(i*2)*.8),i/240.0)
		var patch:=long_path.update(); maximum_tail=maxi(maximum_tail,patch.tail.size())
		maximum_update=maxf(maximum_update,(Time.get_ticks_usec()-update_started)/1000.0)
	var elapsed:=(Time.get_ticks_usec()-started)/1000.0
	print("2500 streaming updates: %.1f ms; mean: %.2f ms; peak: %.2f ms; maximum tail vertices: %d" % [elapsed,elapsed/2500,maximum_update,maximum_tail])
	check(maximum_tail<200,"Streaming preview updates have a bounded tail")
	check(elapsed/2500<4.0,"Streaming correction fits within a small fraction of a 60 FPS frame budget")
	print("Stroke correction checks: %d failures" % failures); quit(failures)
