class_name KiwiStrokeCorrector
extends RefCounted
## Streaming path correction in document coordinates, independent of painting.
## Arc-length samples make filtering independent of mouse event frequency.
## Only a short, revisable tail is fitted; older curve segments are sealed.

const SUPPORT := 54
const CORNER_SUPPORT := 12
const TAIL := 76
## Document pixels: closure must not grow with smoothing scale or brush width.
const CONNECTION_RANGE := 16.0
var strength := 0.5
var correction_scale := 1.0
var spacing := 1.0
var points := PackedVector2Array()
var times := PackedFloat64Array()
var knots := PackedVector2Array()
var corners := PackedByteArray()
var _tip := Vector2.ZERO
var _last := Vector2.ZERO
var _last_time := 0.0
var _tip_time := 0.0
var _carry := 0.0
var _sealed := 0
var _dirty := true
var _left_corner := PackedInt32Array()
var _right_corner := PackedInt32Array()
var _turn_prefix := PackedFloat64Array()
var _fit_first := PackedInt32Array()
var _fit_last := PackedInt32Array()
var _fit_radius := PackedFloat64Array()
var _fit_edge := PackedVector2Array()
var _raw_bounds:=Rect2()
var _shape_rejected:=false
var _gap_closed:=false

func begin(point: Vector2,amount: float,_brush_size: float,time: float=0.0,scale: float=1.0) -> void:
	strength=clampf(amount,0.0,1.0)
	correction_scale=clampf(scale,.1,16.0)
	# Stabilization describes the drawn path, not the width of its paint. Thin
	# outlines need the same ability to remove broad wobble as large brushes.
	spacing=1.25*correction_scale
	points=PackedVector2Array([point]); times=PackedFloat64Array([time])
	knots=PackedVector2Array([point]); corners=PackedByteArray([1])
	_tip=point; _last=point; _last_time=time; _tip_time=time
	_carry=0.0; _sealed=0; _dirty=true
	_left_corner.clear(); _right_corner.clear()
	_turn_prefix=PackedFloat64Array([0.0,0.0])
	_fit_first.clear(); _fit_last.clear(); _fit_radius.clear(); _fit_edge.clear()
	_raw_bounds=Rect2(point,Vector2.ZERO)
	_shape_rejected=false
	_gap_closed=false

func add(point: Vector2,time: float) -> void:
	var distance:=_last.distance_to(point)
	if distance<0.00001: return
	var direction:=(point-_last)/distance
	var travel:=spacing-_carry
	while travel<=distance:
		points.append(_last+direction*travel)
		times.append(lerpf(_last_time,time,travel/distance))
		travel+=spacing
	_carry=fmod(_carry+distance,spacing)
	_last=point; _last_time=time; _tip=point; _tip_time=time; _dirty=true
	_raw_bounds=_raw_bounds.expand(point)

func _raw(index: int) -> Vector2:
	return points[index] if index<points.size() else _tip

func _time(index: int) -> float:
	return times[index] if index<times.size() else _tip_time

func _corner(index: int,count: int) -> bool:
	if index<CORNER_SUPPORT or index>count-CORNER_SUPPORT-1: return false
	var incoming:=_raw(index)-_raw(index-CORNER_SUPPORT)
	var outgoing:=_raw(index+CORNER_SUPPORT)-_raw(index)
	if incoming.length()<spacing*CORNER_SUPPORT*.75 or outgoing.length()<spacing*CORNER_SUPPORT*.75: return false
	var turn:=absf(incoming.angle_to(outgoing))
	if turn<1.05: return false
	# A corner concentrates a sustained turn at one knot. A smooth arc spreads
	# the turn over many knots; alternating jitter has inconsistent side vectors.
	var immediate:=absf((_raw(index)-_raw(index-1)).angle_to(_raw(index+1)-_raw(index)))
	var left_turn:=absf((_raw(index-2)-_raw(index-CORNER_SUPPORT)).angle_to(incoming))
	var right_turn:=absf(outgoing.angle_to(_raw(index+CORNER_SUPPORT)-_raw(index+2)))
	return immediate>turn*.4 and left_turn<.2 and right_turn<.2

func _fit(index: int,count: int) -> Vector2:
	if index==0 or index==count-1 or corners[index]!=0 or strength<=0.0:
		_fit_radius[index]=-1.0; return _raw(index)
	var first:=maxi(0,index-SUPPORT); var last:=mini(count-1,index+SUPPORT)
	var radius:=2.0+34.0*pow(strength,1.2)
	# Do not blend across a deliberate corner, including the anchored start.
	first=maxi(first,_left_corner[index])
	last=mini(last,_right_corner[index])
	# Accumulated turning over the whole fit distinguishes broad bends from
	# jitter (which turns back and cancels). Narrow support continuously before
	# it spans too much of a loop; never switch fits on a single sample's sign.
	var curve_first:=maxi(first,index-ceili(radius))
	var curve_last:=mini(last,index+ceili(radius))
	var curvature:=absf(_turn_prefix[curve_last+1]-_turn_prefix[curve_first])/maxi(1,curve_last-curve_first+1)
	if curvature>.0001: radius=minf(radius,maxf(1.5,.6/curvature))
	var s0:=0.0; var s1:=0.0; var s2:=0.0; var s3:=0.0; var s4:=0.0
	var b0:=Vector2.ZERO; var b1:=Vector2.ZERO; var b2:=Vector2.ZERO
	# Fit every knot: sparse sampling aliases detail and changes phase between
	# neighboring fits. Reuse settled fits to keep the live preview inexpensive.
	first=maxi(first,index-ceili(radius*1.6)); last=mini(last,index+ceili(radius*1.6))
	var edge:=_raw(last)
	if _fit_first[index]==first and _fit_last[index]==last and _fit_radius[index]==radius and _fit_edge[index]==edge:
		return knots[index]
	_fit_first[index]=first; _fit_last[index]=last; _fit_radius[index]=radius; _fit_edge[index]=edge
	var center:=_raw(index)
	for other in range(first,last+1):
		var coordinate:=float(other-index)
		if other==points.size(): coordinate-=1.0-points[-1].distance_to(_tip)/spacing
		var t:=coordinate/radius
		var t2:=t*t; var weight:=exp(-2.0*t2)
		var weighted:=((points[other] if other<points.size() else _tip)-center)*weight
		s0+=weight; s1+=weight*t; s2+=weight*t2; s3+=weight*t2*t; s4+=weight*t2*t2
		b0+=weighted; b1+=weighted*t; b2+=weighted*t2
	var determinant:=s0*(s2*s4-s3*s3)-s1*(s1*s4-s3*s2)+s2*(s1*s3-s2*s2)
	if absf(determinant)<.000001: return _raw(index)
	# Weighted quadratic regression follows sustained curvature. At full
	# strength use the complete fitted path instead of retaining raw wobble.
	var offset:=(b0*(s2*s4-s3*s3)+b1*(s2*s3-s1*s4)+b2*(s1*s3-s2*s2))/determinant
	var amount:=1.0-pow(1.0-strength,1.5)
	var limit:=spacing*radius*.5*strength
	return _raw(index)+offset.limit_length(limit)*amount

func _tangent(index: int) -> Vector2:
	if corners[index]!=0: return Vector2.ZERO
	if index==0: return knots[mini(1,knots.size()-1)]-knots[0]
	if index==knots.size()-1: return knots[index]-knots[index-1]
	var a:=knots[index]-knots[index-1]; var b:=knots[index+1]-knots[index]
	return ((a+b)*.5).limit_length(minf(a.length(),b.length())*1.5)

func _path(first: int,last: int) -> PackedVector2Array:
	var result:=PackedVector2Array([knots[first]])
	if strength<=0.0:
		for index in range(first+1,last+1): result.append(knots[index])
		return result
	for index in range(first,last):
		var a:=knots[index]; var b:=knots[index+1]
		var ta:=_tangent(index); var tb:=_tangent(index+1)
		if corners[index]!=0: ta=b-a
		if corners[index+1]!=0: tb=b-a
		var divisions:=clampi(ceili(a.distance_to(b)/.75),1,12)
		for step in range(1,divisions+1):
			var t:=float(step)/divisions; var t2:=t*t; var t3:=t2*t
			result.append(a*(2*t3-3*t2+1)+ta*(t3-2*t2+t)+b*(-2*t3+3*t2)+tb*(t3-t2))
	return result

func _close_gap(count: int) -> PackedVector2Array:
	var limit:=CONNECTION_RANGE
	if count<32 or points[0].distance_to(_tip)>limit: return PackedVector2Array()
	if minf(_raw_bounds.size.x,_raw_bounds.size.y)<limit*2 or count*spacing<limit*8: return PackedVector2Array()
	var area:=0.0; var stride:=maxi(1,count/128)
	for index in range(0,count,stride): area+=knots[index].cross(knots[mini(count-1,index+stride)])
	area+=knots[-1].cross(knots[0])
	if absf(area)*.5<_raw_bounds.get_area()*.15: return PackedVector2Array()
	# Replace just the seam neighborhood with two joined Hermite curves.
	# This closes gaps without leaving an overlap, hook or straight connector.
	var span:=mini(12,(count-1)/5)
	var first:=knots[span]; var last:=knots[count-1-span]
	var join:=points[0]
	var incoming:=(last-knots[count-1-span-3]).normalized()
	var outgoing:=(knots[span+3]-first).normalized()
	var tangent:=(first-last).normalized()
	var sharp:=absf(incoming.angle_to(outgoing))>1.1
	var joint_length:=minf(last.distance_to(join),first.distance_to(join))
	var result:=_path(span,count-1-span)
	for part in 2:
		var a:=last if part==0 else join; var b:=join if part==0 else first
		var ta:=incoming*a.distance_to(b) if part==0 else (outgoing if sharp else tangent)*joint_length
		var tb:=(incoming if sharp else tangent)*joint_length if part==0 else outgoing*a.distance_to(b)
		var divisions:=clampi(ceili(a.distance_to(b)/maxf(.5,spacing*.5)),8,64)
		for step in range(1,divisions+1):
			var t:=float(step)/divisions; var t2:=t*t; var t3:=t2*t
			result.append(a*(2*t3-3*t2+1)+ta*(t3-2*t2+t)+b*(-2*t3+3*t2)+tb*(t3-t2))
	result[-1]=result[0]
	return result

func update() -> Dictionary:
	if not _dirty: return {}
	_dirty=false
	var previous_count:=knots.size()
	var count:=points.size()+(0 if points[-1].is_equal_approx(_tip) else 1)
	# Prefix sums keep curvature measurement constant-time for each fitted knot.
	_turn_prefix.resize(count+1)
	for index in range(maxi(0,previous_count-3),count):
		var turn:=0.0
		if index>=2 and index<count-2:
			turn=(_raw(index)-_raw(index-2)).angle_to(_raw(index+2)-_raw(index))*.25
		_turn_prefix[index+1]=_turn_prefix[index]+turn
	knots.resize(count); corners.resize(count)
	_fit_first.resize(count); _fit_last.resize(count); _fit_radius.resize(count); _fit_edge.resize(count)
	var start:=maxi(0,previous_count-1-CORNER_SUPPORT)
	for index in range(start,count): corners[index]=1 if index==0 or index==count-1 or _corner(index,count) else 0
	_left_corner.resize(count); _right_corner.resize(count)
	var cache_start:=maxi(0,previous_count-1-SUPPORT*2-CORNER_SUPPORT)
	var left:=_left_corner[cache_start-1] if cache_start>0 else 0
	if cache_start>0 and corners[cache_start-1]!=0: left=cache_start-1
	for index in range(cache_start,count):
		_left_corner[index]=left
		if corners[index]!=0: left=index
	var right:=count-1
	for index in range(count-1,cache_start-1,-1):
		_right_corner[index]=right
		if corners[index]!=0: right=index
	# Refit only knots whose support gained new samples or new corner evidence.
	# The rest of the mutable tail is already settled and needs no recomputation.
	for index in range(maxi(_sealed+1,previous_count-1-SUPPORT-CORNER_SUPPORT),count): knots[index]=_fit(index,count)
	knots[0]=points[0]
	var sealed:=maxi(_sealed,count-TAIL)
	var fixed:=_path(_sealed,sealed) if sealed>_sealed else PackedVector2Array()
	var tail:=_path(sealed,count-1)
	_sealed=sealed
	var patch: Dictionary={"fixed":fixed,"tail":tail}
	if _shape_rejected:
		patch.replace=_path(0,count-1); return patch
	var closed:=_close_gap(count)
	if not closed.is_empty(): patch.replace=closed; _gap_closed=true
	elif _gap_closed:
		_shape_rejected=true; patch.replace=_path(0,count-1)
	return patch
