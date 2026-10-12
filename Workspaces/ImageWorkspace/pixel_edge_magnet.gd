class_name KiwiPixelEdgeMagnet
extends RefCounted
## Continuity-constrained ridge paths, shared by brush and boundary bucket.

var field: KiwiPixelEdgeField
var previous: int=-1

func follow(point: Vector2,threshold: float,direction: Vector2) -> PackedVector2Array:
	var target:=field.nearest(point,threshold,previous,direction)
	if target<0:
		previous=-1
		return PackedVector2Array()
	if previous<0:
		previous=target; return PackedVector2Array([field.refine(target)])
	# Search toward the cursor with a strict per-input budget. A broad flood
	# through textured edges can otherwise queue seconds of mouse input.
	var started:=Time.get_ticks_usec()
	var parents:={previous:-1}
	var queue: Array[Vector2]=[Vector2(0,previous)]
	var origin:=field.position(previous); var destination:=field.position(target)
	var maximum:=minf(160,maxf(24,origin.distance_to(point)*1.5+16))
	var visited:=0
	while not queue.is_empty() and visited<256 and Time.get_ticks_usec()-started<2000 and not parents.has(target):
		var i:=int(KiwiPixelObjectSegmenter.heap_pop(queue).y); visited+=1
		for next in field.neighbors(i,threshold):
			var position:=field.position(next)
			if not parents.has(next) and position.distance_to(origin)<=maximum and position.distance_to(Geometry2D.get_closest_point_to_segment(position,origin,destination))<=24:
				parents[next]=i
				KiwiPixelObjectSegmenter.heap_push(queue,Vector2(position.distance_squared_to(destination),next))
	if not parents.has(target):
		# Reacquire immediately. Returning only the new point starts a separate
		# stamp, so no line is painted across the gap to the old contour.
		previous=target
		return PackedVector2Array([field.refine(target)])
	var path:=PackedVector2Array(); var i:=target
	while i>=0:
		if path.size()>=128 or Time.get_ticks_usec()-started>4000:
			previous=target
			return PackedVector2Array([field.refine(target)])
		path.append(field.refine(i)); i=int(parents[i])
	path.reverse(); previous=target; return path

func connected(point: Vector2,threshold: float) -> PackedVector2Array:
	var seed:=field.nearest(point,threshold)
	if seed<0: return PackedVector2Array()
	var visited:={seed:true}; var path:=PackedVector2Array()
	var queue:=PackedInt32Array([seed]); var head:=0
	# Select the entire connected boundary, including corners and branches.
	# The caller stamps these independently, never connecting separate branches.
	while head<queue.size():
		var current:=queue[head]; head+=1; path.append(field.refine(current))
		for next in field.neighbors(current,threshold):
			if not visited.has(next): visited[next]=true; queue.append(next)
	return path

static func paint_band(mask: Image,path: PackedVector2Array,width: float,domain: Rect2i,tint: Color,connect: bool=true) -> void:
	var radius:=maxf(.5,width*.5)
	var spacing:=maxf(.5,width*.2)
	var stamps:=PackedVector2Array()
	if connect and not path.is_empty():
		stamps.append(path[0]); var remaining:=spacing
		for index in range(1,path.size()):
			var a:=path[index-1]; var b:=path[index]; var length:=a.distance_to(b)
			var offset:=remaining
			while offset<=length:
				stamps.append(a.lerp(b,offset/maxf(.00001,length))); offset+=spacing
			remaining=offset-length
		if stamps[-1].distance_to(path[-1])>.01: stamps.append(path[-1])
	else: stamps=path
	for p in stamps:
		for y in range(maxi(domain.position.y,floori(p.y-radius)),mini(domain.end.y,ceili(p.y+radius))):
			var dy:=y+.5-p.y
			if absf(dy)>radius: continue
			var span:=sqrt(maxf(0,radius*radius-dy*dy))
			var left:=maxi(domain.position.x,ceili(p.x-span-.5)); var right:=mini(domain.end.x,ceili(p.x+span-.5))
			if right>left: mask.fill_rect(Rect2i(left,y,right-left,1),tint)
