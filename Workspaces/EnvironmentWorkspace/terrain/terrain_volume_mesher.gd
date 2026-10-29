extends RefCounted
## Pure CPU tetrahedral extraction of one solid field. Surface terrain and cave
## voids share the same isosurface, including real openings through the surface.
const OFFSETS:=[Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(0,1,1),Vector3i(1,1,1)]
const TETRAHEDRA:=[[0,1,3,7],[0,3,2,7],[0,2,6,7],[0,6,4,7],[0,4,5,7],[0,5,1,7]]
var terrain: KiwiEnvironmentTerrain
var caves: Array[KiwiTerrainCave]=[]
var cave_bounds: Array[AABB]=[]
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var uv:=PackedVector2Array()
var indices:=PackedInt32Array()
var triangle_kind:=PackedByteArray()
var _edges: Dictionary={}
var _epsilon:=.05
var _origin:=Vector3.ZERO
var _spacing:=Vector3.ONE
var _counts:=Vector3i.ONE
var _values:=PackedFloat32Array()
func build(source: KiwiEnvironmentTerrain,coordinate: Vector2i,sources: Array[KiwiTerrainCave],height_step: float=1.,cell_budget: int=200000,cancel: Callable=Callable()) -> Dictionary:
	var started:=Time.get_ticks_usec(); terrain=source; terrain.prepare(cancel); vertices=PackedVector3Array(); normals=PackedVector3Array(); uv=PackedVector2Array(); indices=PackedInt32Array(); triangle_kind=PackedByteArray(); _edges.clear(); caves.clear(); cave_bounds.clear()
	var start:=coordinate*terrain.CHUNK_CELLS; var cells:=Vector2i(mini(terrain.CHUNK_CELLS,terrain.resolution-1-start.x),mini(terrain.CHUNK_CELLS,terrain.resolution-1-start.y)); var horizontal:=terrain.dimensions/(terrain.resolution-1); var minimum:=INF; var maximum:=-INF
	if cells.x<=0 or cells.y<=0: return {"error":"The volume chunk is outside its terrain."}
	for z in cells.y+1:
		for x in cells.x+1: minimum=minf(minimum,terrain.height(start.x+x,start.y+z)); maximum=maxf(maximum,terrain.height(start.x+x,start.y+z))
	var step:=maxf(.1,height_step); var chunk_bounds:=AABB(Vector3((float(start.x)/(terrain.resolution-1)-.5)*terrain.dimensions.x,-100000.,(float(start.y)/(terrain.resolution-1)-.5)*terrain.dimensions.y),Vector3(cells.x*horizontal.x,200000.,cells.y*horizontal.y)).grow(.001)
	for cave in sources:
		if cave==null or not cave.enabled: continue
		var box:=cave.bounds()
		if not box.intersects(chunk_bounds): continue
		cave.prepare(); caves.append(cave); cave_bounds.append(box); minimum=minf(minimum,box.position.y)
	var y_low:=floori(minimum/step)-2; var y_high:=ceili(maximum/step)+2; _counts=Vector3i(cells.x+1,y_high-y_low+1,cells.y+1); var cells_total:=cells.x*cells.y*(_counts.y-1)
	if cells_total>cell_budget: return {"error":"Cave voxel budget exceeded (%d cells). Increase vertical voxel size, reduce depth, or generate a smaller region."%cells_total,"cells":cells_total}
	_spacing=Vector3(horizontal.x,step,horizontal.y); _epsilon=minf(minf(horizontal.x,horizontal.y),step)*.2; _origin=Vector3(chunk_bounds.position.x+.001,y_low*step,chunk_bounds.position.z+.001); _values=PackedFloat32Array(); _values.resize(_counts.x*_counts.y*_counts.z)
	for z in _counts.z:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for x in _counts.x:
			if cancel.is_valid() and cancel.call(): return {"cancelled":true}
			var world_x:=_origin.x+x*_spacing.x; var world_z:=_origin.z+z*_spacing.z; var elevation:=_height(Vector2(world_x,world_z))
			for y in _counts.y:
				if y%8==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true}
				var point:=Vector3(world_x,_origin.y+y*_spacing.y,world_z); _values[_index(Vector3i(x,y,z))]=_void_subtracted(point,point.y-elevation)
	for z in cells.y:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for y in _counts.y-1:
			if cancel.is_valid() and cancel.call(): return {"cancelled":true}
			for x in cells.x:
				var corner_ids:=PackedInt32Array(); var has_air:=false; var has_solid:=false
				for offset: Vector3i in OFFSETS:
					var id:=_index(Vector3i(x,y,z)+offset); corner_ids.append(id)
					if _values[id]<0.: has_solid=true
					else: has_air=true
				if not has_air or not has_solid: continue
				for tetrahedron: Array in TETRAHEDRA:
					var inside:=PackedInt32Array(); var outside:=PackedInt32Array()
					for corner: int in tetrahedron:
						var id:=corner_ids[corner]
						if _values[id]<0.: inside.append(id)
						else: outside.append(id)
					if inside.size()==1: _triangle(_edge(inside[0],outside[0]),_edge(inside[0],outside[1]),_edge(inside[0],outside[2]))
					elif inside.size()==3: _triangle(_edge(outside[0],inside[0]),_edge(outside[0],inside[1]),_edge(outside[0],inside[2]))
					elif inside.size()==2:
						var a:=_edge(inside[0],outside[0]); var b:=_edge(inside[0],outside[1]); var c:=_edge(inside[1],outside[0]); var d:=_edge(inside[1],outside[1]); _triangle(a,b,c); _triangle(b,d,c)
	return {"vertices":vertices,"normals":normals,"uv":uv,"indices":indices,"triangle_kind":triangle_kind,"cells":cells_total,"milliseconds":float(Time.get_ticks_usec()-started)/1000.,"cancelled":false,"error":""}
func _height(point: Vector2) -> float:
	var p:=((point/terrain.dimensions+Vector2.ONE*.5)*(terrain.resolution-1)).clamp(Vector2.ZERO,Vector2.ONE*(terrain.resolution-1)); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell)
	return lerpf(lerpf(terrain.height(cell.x,cell.y),terrain.height(cell.x+1,cell.y),f.x),lerpf(terrain.height(cell.x,cell.y+1),terrain.height(cell.x+1,cell.y+1),f.x),f.y)
func _void_subtracted(point: Vector3,surface: float) -> float:
	var distance:=INF
	for index in caves.size():
		if cave_bounds[index].has_point(point): distance=minf(distance,caves[index].distance(point))
	return maxf(surface,-distance)
func density(point: Vector3) -> float: return _void_subtracted(point,point.y-_height(Vector2(point.x,point.z)))
func _gradient(point: Vector3) -> Vector3:
	var x:=Vector3(_epsilon,0,0); var y:=Vector3(0,_epsilon,0); var z:=Vector3(0,0,_epsilon); return Vector3(density(point+x)-density(point-x),density(point+y)-density(point-y),density(point+z)-density(point-z)).normalized()
func _index(point: Vector3i) -> int: return point.x+point.y*_counts.x+point.z*_counts.x*_counts.y
func _position(index: int) -> Vector3:
	var x:=index%_counts.x; var y:=int(index/_counts.x)%_counts.y; var z:=int(index/(_counts.x*_counts.y)); return _origin+Vector3(x,y,z)*_spacing
func _edge(a: int,b: int) -> int:
	var key: int=(mini(a,b)<<32)|maxi(a,b)
	if _edges.has(key): return int(_edges[key])
	var amount:=clampf(_values[a]/(_values[a]-_values[b]),0.,1.); var point:=_position(a).lerp(_position(b),amount); var index:=vertices.size(); vertices.append(point); normals.append(_gradient(point)); uv.append(Vector2(point.x,point.z)/terrain.dimensions); _edges[key]=index; return index
func _triangle(a: int,b: int,c: int) -> void:
	var cross: Vector3=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
	if cross.length_squared()<.0000000001: return
	var center: Vector3=(vertices[a]+vertices[b]+vertices[c])/3.; triangle_kind.append(1 if center.y<_height(Vector2(center.x,center.z))-_epsilon*.5 else 0)
	if cross.dot(normals[a]+normals[b]+normals[c])>0.: indices.append_array(PackedInt32Array([a,c,b]))
	else: indices.append_array(PackedInt32Array([a,b,c]))
