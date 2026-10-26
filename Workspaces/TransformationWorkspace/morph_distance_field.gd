class_name KiwiMorphDistanceField
extends RefCounted
## Two-pass Euclidean-nearest propagation; signed occupancy plus nearest ink UV.
## Never run per frame. Both holes and disconnected islands are represented.
static func build(image: Image, analysis: Dictionary, other_palette: Array) -> Image:
	var size := image.get_size(); var n := size.x*size.y; var inside := PackedVector2Array(); var outside := PackedVector2Array(); inside.resize(n); outside.resize(n)
	var mask: PackedByteArray=analysis.get("mask",PackedByteArray()); var empty := mask.is_empty()
	for i in n:
		var p := Vector2(i%size.x,i/size.x)
		inside[i]=p if not empty and mask[i]!=0 else Vector2(-100000,-100000)
		# Treat beyond-image space as empty, including opaque full-frame drawings.
		var edge := Vector2(-1,p.y)
		for candidate in [Vector2(size.x,p.y),Vector2(p.x,-1),Vector2(p.x,size.y)]:
			if p.distance_squared_to(candidate)<p.distance_squared_to(edge): edge=candidate
		outside[i]=p if empty or mask[i]==0 else edge
	inside=propagate(inside,size); outside=propagate(outside,size)
	var values := PackedFloat32Array(); values.resize(n*4)
	for i in n:
		var p := Vector2(i%size.x,i/size.x); var occupied := not empty and mask[i]!=0
		var signed_distance := (p.distance_to(outside[i]) if occupied else -minf(float(maxi(size.x,size.y)),p.distance_to(inside[i])))/maxi(size.x,size.y)
		var nearest := ((inside[i]+Vector2.ONE*.5)/Vector2(size)).clamp(Vector2.ZERO,Vector2.ONE)
		var color := image.get_pixelv(Vector2i(p)); var novelty := 0.
		if occupied and not other_palette.is_empty():
			var rgb := Vector3(color.r,color.g,color.b); var gap := INF
			for feature: Dictionary in other_palette: gap=minf(gap,rgb.distance_squared_to(feature.color))
			novelty=smoothstep(.015,.08,gap)
		values[i*4]=signed_distance; values[i*4+1]=nearest.x; values[i*4+2]=nearest.y; values[i*4+3]=novelty
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,values.to_byte_array())
static func propagate(field: PackedVector2Array,size: Vector2i) -> PackedVector2Array:
	var n := field.size()
	for pass_index in 2:
		var direction := -1 if pass_index==0 else 1
		var neighbors := [Vector2i(direction,0),Vector2i(-1,direction),Vector2i(0,direction),Vector2i(1,direction)]
		for step in n:
			var i := step if pass_index==0 else n-1-step; var x := i%size.x; var y := i/size.x; var p := Vector2(x,y); var best := field[i]; var distance := p.distance_squared_to(best)
			for delta: Vector2i in neighbors:
				var nx: int=x+delta.x; var ny: int=y+delta.y
				if nx<0 or nx>=size.x or ny<0 or ny>=size.y: continue
				var candidate := field[ny*size.x+nx]; var gap := p.distance_squared_to(candidate)
				if gap<distance: distance=gap; best=candidate
			field[i]=best
	return field
