class_name KiwiImageWarpBrush
extends RefCounted
## Compact inverse-field composition. Work scales with field nodes in the brush,
## not the source bitmap's pixel count.
static func stroke(data: KiwiImageWarpData,extent: Vector2,from: Vector2,to: Vector2,diameter: float,strength: float,hardness: float,kind: String,elapsed: float=1.0) -> bool:
	if strength<=0: return false
	if kind in ["restore","smooth"]: data.rebuild()
	var radius:=maxf(.5,diameter*.5)
	var distance:=((to-from)*extent).length()
	if kind=="push" and distance<.0001: return false
	var steps:=clampi(ceili(distance/maxf(1,radius*.3)),1,24)
	for step in steps:
		var center:=from.lerp(to,float(step+1)/steps)
		var movement:=(to-from)/steps
		_dab(data,extent,center,movement,radius,strength/float(steps) if kind!="push" else strength,hardness,kind,elapsed)
	data.touch(); return true

static func _dab(data: KiwiImageWarpData,extent: Vector2,center: Vector2,movement: Vector2,radius: float,strength: float,hardness: float,kind: String,elapsed: float) -> void:
	var old:=data.displacement.duplicate()
	var reach:=Vector2.ONE*radius/extent.max(Vector2.ONE)
	var begin:=Vector2i(((center-reach)*Vector2(data.grid_size-Vector2i.ONE)).floor()).max(Vector2i.ZERO)
	var end:=Vector2i(((center+reach)*Vector2(data.grid_size-Vector2i.ONE)).ceil()).min(data.grid_size-Vector2i.ONE)
	for y in range(begin.y,end.y+1):
		for x in range(begin.x,end.x+1):
			var index:=y*data.grid_size.x+x; var uv:=data.node_uv(index)
			var relative:=(uv-center)*extent; var distance:=relative.length()/radius
			if distance>=1: continue
			var feather:=maxf(.08,1-hardness*.92)
			var t:=clampf((1-distance)/feather,0,1)
			var weight:=t*t*(3-2*t)
			if kind=="freeze" or kind=="thaw":
				data.freeze[index]=lerpf(data.freeze[index],1.0 if kind=="freeze" else 0.0,clampf(weight*strength*.25*elapsed,0,1)); continue
			weight*=1-data.freeze[index]
			if data.restriction.size()==old.size(): weight*=data.restriction[index]
			var amount:=clampf(weight*strength*elapsed,0,1)
			if kind=="restore":
				data.displacement[index]=old[index]-data.inverse_offset(index)*amount*.2
			elif kind=="smooth":
				var sum:=data.inverse_offset(y*data.grid_size.x+maxi(0,x-1))+data.inverse_offset(y*data.grid_size.x+mini(data.grid_size.x-1,x+1))+data.inverse_offset(maxi(0,y-1)*data.grid_size.x+x)+data.inverse_offset(mini(data.grid_size.y-1,y+1)*data.grid_size.x+x)
				data.displacement[index]=old[index]+(sum*.25-data.inverse_offset(index))*amount*.6
			else:
				var offset:=-movement*weight*strength
				if kind in ["pinch","bulge"]: offset=(uv-center)*amount*(.1 if kind=="pinch" else -.1)
				elif kind in ["twirl_cw","twirl_ccw"]: offset=(relative.rotated(amount*(-.08 if kind=="twirl_cw" else .08))-relative)/extent
				data.displacement[index]=offset+KiwiImageWarpData.sample_grid(old,data.grid_size,uv+offset)
