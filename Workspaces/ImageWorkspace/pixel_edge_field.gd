class_name KiwiPixelEdgeField
extends RefCounted
## Immutable, reusable gradient field. Coordinates exposed to clients are
## document pixels, independent of zoom and the reduced analysis resolution.

var source: Image
var domain: Rect2i
var bitmap: Image
var size: Vector2i
var step: Vector2
var strength:=PackedFloat32Array()
var normal:=PackedVector2Array()
var ridges:=PackedByteArray()
var colors:=PackedColorArray()

func build(image: Image,area: Rect2i,maximum: int=768) -> void:
	source=image; domain=area.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	bitmap=image.get_region(domain); bitmap.convert(Image.FORMAT_RGBA8)
	var ratio:=minf(1.0,float(maximum)/maxi(domain.size.x,domain.size.y))
	if ratio<1: bitmap.resize(maxi(1,roundi(domain.size.x*ratio)),maxi(1,roundi(domain.size.y*ratio)),Image.INTERPOLATE_BILINEAR)
	size=bitmap.get_size(); step=Vector2(domain.size)/Vector2(size)
	var bytes:=bitmap.get_data(); var count:=size.x*size.y
	colors.resize(count); strength.resize(count); normal.resize(count); ridges.resize(count)
	for i in count:
		var a:=bytes[i*4+3]/255.0
		# Rendered layer sources are premultiplied; alpha is analyzed separately.
		colors[i]=Color(bytes[i*4]/255.0/maxf(a,.001),bytes[i*4+1]/255.0/maxf(a,.001),bytes[i*4+2]/255.0/maxf(a,.001),a)
	# Analyze premultiplied color: invisible RGB must never create an edge.
	# A separable binomial filter removes isolated noise before the Sobel tensor.
	var filtered:=PackedColorArray(); filtered.resize(count)
	var smooth:=PackedColorArray(); smooth.resize(count)
	for y in size.y:
		for x in size.x:
			var sum:=Color(0,0,0,0)
			for k in range(-1,2):
				var c:=colors[y*size.x+clampi(x+k,0,size.x-1)]
				sum+=Color(c.r*c.a,c.g*c.a,c.b*c.a,c.a)*(2.0 if k==0 else 1.0)
			filtered[y*size.x+x]=sum*.25
	for y in size.y:
		for x in size.x:
			smooth[y*size.x+x]=(filtered[maxi(0,y-1)*size.x+x]+filtered[y*size.x+x]*2+filtered[mini(size.y-1,y+1)*size.x+x])*.25
	for y in size.y:
		for x in size.x:
			var i:=y*size.x+x
			var dx:=Color(0,0,0,0); var dy:=Color(0,0,0,0)
			for k in range(-1,2):
				var weight:=2.0 if k==0 else 1.0
				dx+=(smooth[clampi(y+k,0,size.y-1)*size.x+mini(size.x-1,x+1)]-smooth[clampi(y+k,0,size.y-1)*size.x+maxi(0,x-1)])*weight*.25
				dy+=(smooth[mini(size.y-1,y+1)*size.x+clampi(x+k,0,size.x-1)]-smooth[maxi(0,y-1)*size.x+clampi(x+k,0,size.x-1)])*weight*.25
			var xx:=0.0; var yy:=0.0; var xy:=0.0
			for g in [Vector2(dx.r,dy.r),Vector2(dx.g,dy.g),Vector2(dx.b,dy.b),Vector2(dx.a,dy.a)]:
				xx+=g.x*g.x; yy+=g.y*g.y; xy+=g.x*g.y
			var angle:=.5*atan2(2*xy,xx-yy)
			normal[i]=Vector2(cos(angle),sin(angle))
			strength[i]=clampf(sqrt((xx+yy+sqrt((xx-yy)*(xx-yy)+4*xy*xy))*.5),0,1)
	# Nonmaximum suppression thins gradient bands into connected edge ridges.
	for y in size.y:
		for x in size.x:
			var i:=y*size.x+x; var n:=normal[i]
			if strength[i]<.008: continue
			var av:=sample_strength(Vector2(x,y)+n); var bv:=sample_strength(Vector2(x,y)-n)
			if strength[i]>=av-.00001 and strength[i]>=bv-.00001: ridges[i]=1

func sample_strength(p: Vector2) -> float:
	var x:=clampf(p.x,0,size.x-1); var y:=clampf(p.y,0,size.y-1)
	var a:=floori(x); var b:=floori(y)
	return lerpf(lerpf(strength[b*size.x+a],strength[b*size.x+mini(a+1,size.x-1)],x-a),lerpf(strength[mini(b+1,size.y-1)*size.x+a],strength[mini(b+1,size.y-1)*size.x+mini(a+1,size.x-1)],x-a),y-b)

func inside(p: Vector2i) -> bool: return Rect2i(Vector2i.ZERO,size).has_point(p)
func position(i: int) -> Vector2: return Vector2(domain.position)+(Vector2(i%size.x,i/size.x)+Vector2.ONE*.5)*step
func cell(point: Vector2) -> Vector2i: return Vector2i(((point-Vector2(domain.position))/step).floor())
func cutoff(value: float) -> float: return .012+.75*pow(clampf(value,0,1),2)

func nearest(point: Vector2,threshold: float,previous: int=-1,direction: Vector2=Vector2.ZERO) -> int:
	var at:=cell(point); var reach:=Vector2i((Vector2.ONE*16/step).ceil())
	var best:=-1; var score:=INF
	for y in range(maxi(0,at.y-reach.y),mini(size.y,at.y+reach.y+1)):
		for x in range(maxi(0,at.x-reach.x),mini(size.x,at.x+reach.x+1)):
			var i:=y*size.x+x
			if ridges[i]==0 or strength[i]<cutoff(threshold)*(.4 if previous>=0 else 1.0): continue
			var distance:=position(i).distance_to(point)
			if distance>16: continue
			var value:=distance+2.0*(1.0-strength[i])
			if previous>=0: value+=position(i).distance_to(position(previous))*.1+3.0*(1.0-absf(normal[i].dot(normal[previous])))
			if not direction.is_zero_approx(): value+=absf(normal[i].dot(direction.normalized()))*3
			if value<score: score=value; best=i
	return best

func neighbors(i: int,threshold: float) -> PackedInt32Array:
	var result:=PackedInt32Array(); var at:=Vector2i(i%size.x,i/size.x)
	for delta in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]:
		var p: Vector2i=at+delta
		if inside(p):
			var next:=p.y*size.x+p.x
			if ridges[next]!=0 and strength[next]>=cutoff(threshold)*.4: result.append(next)
	# Bridge only a single missing ridge cell, along its tangent and with
	# gradient evidence in the gap. Never bridge nearby parallel contours.
	for delta in [Vector2i(-2,-1),Vector2i(-2,0),Vector2i(-2,1),Vector2i(-1,-2),Vector2i(0,-2),Vector2i(1,-2),Vector2i(2,-1),Vector2i(2,0),Vector2i(2,1),Vector2i(-1,2),Vector2i(0,2),Vector2i(1,2)]:
		var p: Vector2i=at+delta
		if not inside(p): continue
		var next:=p.y*size.x+p.x
		if ridges[next]==0 or strength[next]<cutoff(threshold)*.4: continue
		if absf(normal[i].dot(Vector2(delta).normalized()))>.55 or absf(normal[next].dot(normal[i]))<.7: continue
		if sample_strength(Vector2(at)+Vector2(delta)*.5)<cutoff(threshold)*.3: continue
		result.append(next)
	return result

func refine(i: int) -> Vector2:
	# Refine only the small neighborhood of a chosen ridge at source resolution.
	var center:=position(i); var reach:=mini(8,ceili(maxf(step.x,step.y)))
	var best:=center; var score:=-INF
	for y in range(maxi(domain.position.y+1,floori(center.y)-reach),mini(domain.end.y-1,ceili(center.y)+reach+1)):
		for x in range(maxi(domain.position.x+1,floori(center.x)-reach),mini(domain.end.x-1,ceili(center.x)+reach+1)):
			var offset:=Vector2(x+.5,y+.5)-center
			# Refine across the contour, never sideways toward a neighboring
			# detail. Broad analysis pixels otherwise jump between nearby edges.
			if absf(offset.dot(normal[i].orthogonal()))>maxf(.75,minf(step.x,step.y)*.5): continue
			var dx:=source.get_pixel(x+1,y)-source.get_pixel(x-1,y)
			var dy:=source.get_pixel(x,y+1)-source.get_pixel(x,y-1)
			var gradient:=maxf(maxf(Vector2(dx.r,dy.r).length(),Vector2(dx.g,dy.g).length()),maxf(Vector2(dx.b,dy.b).length(),Vector2(dx.a,dy.a).length()))
			var value:=gradient-offset.length()*.08
			if value>score: score=value; best=Vector2(x+.5,y+.5)
	return best
