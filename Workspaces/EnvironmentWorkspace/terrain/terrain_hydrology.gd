class_name KiwiTerrainHydrology
extends Resource
## Shared height/drainage/water data. No independent fluid simulation or scene
## nodes: generated channel geometry and water regions consume the same terrain.
const DRY:=-1.0e20
const DIRECTIONS:=[Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(1,-1),Vector2i(-1,1)]
@export var enabled:=true
@export var automatic_rivers:=true
@export var catchment_threshold:=20.
@export var river_width:=1.
@export var river_depth:=1.
@export var flow_speed:=1.
@export var rainfall:=1.
@export var rainfall_variation:=.2
@export var minimum_river_slope:=.002
@export var maximum_rivers:=64
@export var mesh_vertex_budget:=500000
@export var waterfall_drop:=2.
@export var automatic_lakes:=true
@export var lake_minimum_depth:=.4
@export var ocean_enabled:=false
@export var sea_level:=0.
@export var moisture_radius:=8.
@export var manual_rivers: Array[Dictionary]=[]
@export var manual_lakes: Array[Dictionary]=[]
@export var water_color:=Color(.12,.46,.8,.9)
@export var roughness:=.16
@export var wave_strength:=.03
@export var wave_scale:=1.
@export var wave_direction:=Vector2(.8,.3)
@export var material_asset:=""
@export var water_physics:=true
@export var water_density:=1000.
@export var water_drag:=1.
@export var foam_color:=Color(.94,.98,1.,1.)
@export var foam_amount:=.45
@export var waterfall_spray:=true
@export var spray_per_fall:=24
@export var spray_size:=.12
@export var spray_lifetime:=1.2
var _n:=0
var _dimensions:=Vector2.ONE
var _spacing:=Vector2.ONE
var _ground:=PackedFloat32Array()
var _vertices:=PackedVector3Array()
var _normals:=PackedVector3Array()
var _uv:=PackedVector2Array()
var _uv2:=PackedVector2Array()
var _colors:=PackedColorArray()
var _indices:=PackedInt32Array()
var _mesh_error:=""
func geometry_signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([2,enabled,automatic_rivers,catchment_threshold,river_width,river_depth,flow_speed,rainfall,rainfall_variation,minimum_river_slope,maximum_rivers,mesh_vertex_budget,waterfall_drop,automatic_lakes,lake_minimum_depth,ocean_enabled,sea_level,moisture_radius,manual_rivers,manual_lakes])
func signature() -> int: return hash([geometry_signature(),flow_speed,water_color,roughness,wave_strength,wave_scale,wave_direction,material_asset,water_physics,water_density,water_drag,foam_color,foam_amount,waterfall_spray,spray_per_fall,spray_size,spray_lifetime])
func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not is_finite(water_density) or water_density<=0. or not is_finite(water_drag) or water_drag<0.: errors.append("Water density must be positive and drag must be nonnegative finite values.")
	if not is_finite(foam_amount) or not is_finite(spray_size) or spray_size<=0. or not is_finite(spray_lifetime) or spray_lifetime<=0.: errors.append("Waterfall appearance values must be finite with positive size and lifetime.")
	for name in ["catchment_threshold","river_width","river_depth","flow_speed","rainfall","rainfall_variation","minimum_river_slope","waterfall_drop","lake_minimum_depth","sea_level","moisture_radius","roughness","wave_strength","wave_scale"]:
		if not is_finite(float(get(name))): errors.append("Water generation values must be finite."); break
	for river in manual_rivers:
		var points: PackedVector3Array=river.get("points",PackedVector3Array())
		if points.size()<2: errors.append("River paths need at least two points.")
		for point in points:
			if not point.is_finite(): errors.append("River path coordinates must be finite."); break
	return errors
func generate(source: PackedFloat32Array,n: int,dimensions: Vector2,seed: int,cancel: Callable=Callable()) -> Dictionary:
	var started:=Time.get_ticks_usec(); _n=n; _dimensions=dimensions; _spacing=dimensions/maxi(1,n-1); _ground=source; var count:=n*n; var filled:=source.duplicate(); var downstream:=PackedInt32Array(); downstream.resize(count); downstream.fill(-1); var visited:=PackedByteArray(); visited.resize(count); var order:=PackedInt32Array(); var heap: Array[Vector2]=[]; var accumulation:=PackedFloat32Array(); accumulation.resize(count); var levels:=PackedFloat32Array(); levels.resize(count); levels.fill(DRY); var body_kind:=PackedByteArray(); body_kind.resize(count); var delta:=PackedFloat32Array(); delta.resize(count); var flow:=PackedVector2Array(); flow.resize(count); var warnings:=PackedStringArray()
	if not enabled: return {"delta":delta,"levels":levels,"depth":delta.duplicate(),"flow":flow,"paths":[],"mesh":{},"warnings":warnings,"cancelled":false,"milliseconds":0.}
	var errors:=validate()
	if not errors.is_empty(): return {"error":"\n".join(errors)}
	for river in manual_rivers:
		for point: Vector3 in river.get("points",PackedVector3Array()):
			if absf(point.x)>dimensions.x*.5 or absf(point.z)>dimensions.y*.5: return {"error":"River control points must remain inside their terrain."}
	for lake in manual_lakes:
		var center: Vector2=lake.get("center",Vector2.ZERO)
		if absf(center.x)>dimensions.x*.5 or absf(center.y)>dimensions.y*.5: return {"error":"Lake centers must remain inside their terrain."}
	for z in n:
		for x in n:
			if x!=0 and z!=0 and x!=n-1 and z!=n-1: continue
			var index:=x+z*n; visited[index]=1; _push(heap,Vector2(source[index],index))
	while not heap.is_empty():
		if order.size()%128==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true}
		var cell:=_pop(heap); var index:=int(cell.y); order.append(index); var point:=Vector2i(index%n,index/n)
		for direction: Vector2i in DIRECTIONS:
			var next:=point+direction
			if next.x<0 or next.y<0 or next.x>=n or next.y>=n: continue
			var neighbor:=next.x+next.y*n
			if visited[neighbor]!=0: continue
			visited[neighbor]=1; downstream[neighbor]=index; filled[neighbor]=maxf(source[neighbor],filled[index]); _push(heap,Vector2(filled[neighbor],neighbor))
	var rain:=FastNoiseLite.new(); rain.seed=seed+197; rain.frequency=.1
	for index in count:
		var x:=index%n; var z:=int(index/n); var area:=_spacing.x*_spacing.y*(.5 if x==0 or x==n-1 else 1.)*(.5 if z==0 or z==n-1 else 1.); accumulation[index]=maxf(0.,rainfall)*area*maxf(0.,1.+rain.get_noise_2dv(Vector2(_point(index).x,_point(index).z))*clampf(rainfall_variation,0.,1.))
	for position in range(order.size()-1,-1,-1):
		var index:=order[position]; var parent:=downstream[index]
		if parent>=0: accumulation[parent]+=accumulation[index]
	if ocean_enabled:
		var seeds:=PackedInt32Array()
		for index in order:
			var point:=Vector2i(index%n,index/n)
			if (point.x==0 or point.y==0 or point.x==n-1 or point.y==n-1) and source[index]<sea_level: seeds.append(index)
		_flood_water(seeds,sea_level,source,levels,body_kind,1,cancel)
	if automatic_lakes:
		for index in count:
			if source[index]<filled[index]-maxf(.01,lake_minimum_depth) and levels[index]<filled[index]-.0001: _flood_water(PackedInt32Array([index]),filled[index],source,levels,body_kind,2,cancel)
	for lake in manual_lakes:
		if not bool(lake.get("enabled",true)): continue
		var center: Vector2=lake.get("center",Vector2.ZERO); var level:=float(lake.get("level",0.)); var index:=_cell(center)
		if source[index]>=level: warnings.append("A lake center is above its water level; move it into a basin or raise the level."); continue
		_flood_water(PackedInt32Array([index]),level,source,levels,body_kind,2,cancel)
	if cancel.is_valid() and cancel.call(): return {"cancelled":true}
	var paths: Array[Dictionary]=[]
	if automatic_rivers: paths=_rivers(source,filled,downstream,accumulation,levels,cancel)
	for river in manual_rivers:
		if not bool(river.get("enabled",true)): continue
		var points: PackedVector3Array=river.get("points",PackedVector3Array()); var width:=maxf(maxf(_spacing.x,_spacing.y)*1.25,float(river.get("width",river_width))); var depth:=maxf(.01,float(river.get("depth",river_depth))); var follow:=bool(river.get("follow_terrain",true)); var widths:=PackedFloat32Array(); var projected:=PackedVector3Array(); var previous:=INF
		for point in points:
			var height:=_sample(source,Vector2(point.x,point.z))-depth*.35 if follow else point.y
			if not bool(river.get("allow_uphill",false)): height=minf(previous,height)
			previous=height; projected.append(Vector3(point.x,height,point.z)); widths.append(width)
		paths.append({"id":str(river.get("id","manual")),"points":projected,"widths":widths,"depth":depth,"automatic":false})
	if paths.size()>clampi(maximum_rivers,1,256): warnings.append("River count reached its generation budget."); paths.resize(clampi(maximum_rivers,1,256))
	var waterfalls: Array[Dictionary]=[]
	for path in paths:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for point: Vector3 in path.points:
			var index:=_cell(Vector2(point.x,point.z))
			if source[index]<point.y-.001 and levels[index]<point.y-.001: _flood_water(PackedInt32Array([index]),point.y,source,levels,body_kind,2,cancel)
		_carve(path,source,delta,levels,flow,waterfalls)
	var final_ground:=source.duplicate()
	for index in count: final_ground[index]+=delta[index]
	var depth:=PackedFloat32Array(); depth.resize(count); var wet:=PackedByteArray(); wet.resize(count); var any_water:=false
	for index in count:
		if levels[index]>DRY*.5: depth[index]=maxf(0.,levels[index]-final_ground[index]); wet[index]=1 if depth[index]>.0001 else 0; any_water=any_water or wet[index]!=0
	var distance_wet:=_distance(wet,true,cancel); var distance_dry:=_distance(wet,false,cancel); var shore:=PackedFloat32Array(); shore.resize(count); var moisture:=PackedFloat32Array(); moisture.resize(count)
	for index in count: shore[index]=-distance_dry[index] if wet[index]!=0 else distance_wet[index]; moisture[index]=exp(-maxf(0.,shore[index])/maxf(.01,moisture_radius)) if any_water else 0.
	_build_water(paths,final_ground,levels,body_kind,cancel)
	if not _mesh_error.is_empty(): return {"error":_mesh_error}
	return {"delta":delta,"ground":final_ground,"filled":filled,"downstream":downstream,"accumulation":accumulation,"levels":levels,"depth":depth,"flow":flow,"shore_distance":shore,"moisture":moisture,"body_kind":body_kind,"paths":paths,"waterfalls":waterfalls,"mesh":{"vertices":_vertices,"normals":_normals,"uv":_uv,"uv2":_uv2,"colors":_colors,"indices":_indices},"warnings":warnings,"cancelled":cancel.is_valid() and cancel.call(),"error":"","milliseconds":float(Time.get_ticks_usec()-started)/1000.}
func _point(index: int) -> Vector3: return Vector3((float(index%_n)/maxi(1,_n-1)-.5)*_dimensions.x,_ground[index],(float(index/_n)/maxi(1,_n-1)-.5)*_dimensions.y)
func _cell(point: Vector2) -> int:
	var p:=Vector2i(((point/_dimensions+Vector2.ONE*.5)*(_n-1)).round()).clamp(Vector2i.ZERO,Vector2i.ONE*(_n-1)); return p.x+p.y*_n
func _sample(values: PackedFloat32Array,point: Vector2) -> float:
	var p:=((point/_dimensions+Vector2.ONE*.5)*(_n-1)).clamp(Vector2.ZERO,Vector2.ONE*(_n-1)); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var right:=mini(cell.x+1,_n-1); var down:=mini(cell.y+1,_n-1)
	return lerpf(lerpf(values[cell.x+cell.y*_n],values[right+cell.y*_n],f.x),lerpf(values[cell.x+down*_n],values[right+down*_n],f.x),f.y)
static func _push(heap: Array[Vector2],item: Vector2) -> void:
	heap.append(item); var index:=heap.size()-1
	while index>0:
		var parent: int=(index-1)>>1; var other:=heap[parent]
		if other.x<item.x or (other.x==item.x and other.y<=item.y): break
		heap[index]=other; index=parent
	heap[index]=item
static func _pop(heap: Array[Vector2]) -> Vector2:
	var result:=heap[0]; var tail: Vector2=heap.pop_back()
	if heap.is_empty(): return result
	var index:=0
	while index*2+1<heap.size():
		var child:=index*2+1
		if child+1<heap.size() and (heap[child+1].x<heap[child].x or (heap[child+1].x==heap[child].x and heap[child+1].y<heap[child].y)): child+=1
		var next:=heap[child]
		if tail.x<next.x or (tail.x==next.x and tail.y<=next.y): break
		heap[index]=next; index=child
	heap[index]=tail; return result

func _flood_water(seeds: PackedInt32Array,level: float,ground: PackedFloat32Array,levels: PackedFloat32Array,kinds: PackedByteArray,kind: int,cancel: Callable) -> void:
	var queue:=seeds.duplicate(); var seen:={}; var cursor:=0
	while cursor<queue.size():
		if cursor%128==0 and cancel.is_valid() and cancel.call(): return
		var index:=queue[cursor]; cursor+=1
		if seen.has(index): continue
		seen[index]=true
		if ground[index]>=level-.000001 or levels[index]>=level-.000001: continue
		levels[index]=level; kinds[index]=kind; var point:=Vector2i(index%_n,index/_n)
		for direction: Vector2i in DIRECTIONS:
			var next:=point+direction
			if next.x>=0 and next.y>=0 and next.x<_n and next.y<_n: queue.append(next.x+next.y*_n)
func _rivers(source: PackedFloat32Array,filled: PackedFloat32Array,downstream: PackedInt32Array,accumulation: PackedFloat32Array,levels: PackedFloat32Array,cancel: Callable) -> Array[Dictionary]:
	var eligible:=PackedByteArray(); eligible.resize(_n*_n); var parents:=PackedInt32Array(); parents.resize(_n*_n); var heads:=PackedInt32Array(); var threshold:=maxf(.01,catchment_threshold)
	for index in eligible.size():
		if downstream[index]>=0 and accumulation[index]>=threshold and levels[index]<DRY*.5: eligible[index]=1
	for index in eligible.size():
		if eligible[index]!=0 and downstream[index]>=0 and eligible[downstream[index]]!=0: parents[downstream[index]]+=1
	for index in eligible.size():
		if eligible[index]!=0 and parents[index]==0: heads.append(index)
	var sorted:=Array(heads); sorted.sort_custom(func(a: int,b: int): return accumulation[a]>accumulation[b] if accumulation[a]!=accumulation[b] else a<b); var seen:={}; var paths: Array[Dictionary]=[]
	for start: int in sorted:
		if cancel.is_valid() and cancel.call(): return paths
		var cells:=PackedInt32Array(); var current:=start; var length:=0.
		while current>=0 and cells.size()<_n*_n:
			if not cells.is_empty(): length+=_point(current).distance_to(_point(cells[-1]))
			cells.append(current)
			if seen.has(current) or levels[current]>DRY*.5: break
			current=downstream[current]
		if cells.size()<2 or filled[cells[0]]-filled[cells[-1]]<maxf(.0001,length*maxf(0.,minimum_river_slope)): continue
		var points:=PackedVector3Array(); var widths:=PackedFloat32Array(); var depth:=maxf(.01,river_depth)
		for index in cells:
			var point:=_point(index); point.y=float(seen[index]) if seen.has(index) else (levels[index] if levels[index]>DRY*.5 else filled[index]-depth*.35); points.append(point); widths.append(maxf(maxf(_spacing.x,_spacing.y)*1.25,maxf(.1,river_width)*clampf(sqrt(accumulation[index]/threshold),1.,4.)))
		for position in range(points.size()-2,-1,-1):
			var point:=points[position]; point.y=maxf(point.y,points[position+1].y); points[position]=point
		for position in cells.size(): seen[cells[position]]=points[position].y
		paths.append({"id":"drainage:%d"%start,"points":points,"widths":widths,"depth":depth,"automatic":true})
		if paths.size()>clampi(maximum_rivers,1,256): break
	return paths
func _carve(path: Dictionary,source: PackedFloat32Array,delta: PackedFloat32Array,levels: PackedFloat32Array,flow: PackedVector2Array,waterfalls: Array[Dictionary]) -> void:
	var points: PackedVector3Array=path.points; var widths: PackedFloat32Array=path.widths; var depth:=maxf(.01,float(path.depth))
	for segment in points.size()-1:
		var a:=points[segment]; var b:=points[segment+1]; var a2:=Vector2(a.x,a.z); var b2:=Vector2(b.x,b.z); var direction:=b2-a2
		if direction.length_squared()<.000001: continue
		var bank:=maxf(widths[segment],widths[segment+1])*.5/.860662966; var low:=Vector2i(((a2.min(b2)-Vector2.ONE*bank)/_dimensions+Vector2.ONE*.5)*(_n-1)).max(Vector2i.ZERO); var high:=Vector2i((((a2.max(b2)+Vector2.ONE*bank)/_dimensions+Vector2.ONE*.5)*(_n-1)).ceil()).min(Vector2i.ONE*(_n-1))
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var index:=x+z*_n; var point:=_point(index); var p:=Vector2(point.x,point.z); var along:=clampf((p-a2).dot(direction)/direction.length_squared(),0.,1.); var distance:=p.distance_to(a2+direction*along); var width:=lerpf(widths[segment],widths[segment+1],along); var radius:=width*.5/.860662966
				if distance>radius: continue
				var water:=lerpf(a.y,b.y,along); var weight:=maxf(0.,1.-distance*distance/(radius*radius)); var target:=lerpf(source[index],water-depth,weight); delta[index]=minf(delta[index],target-source[index])
				if distance<=width*.5+maxf(_spacing.x,_spacing.y)*.1: levels[index]=maxf(levels[index],water); flow[index]=direction.normalized()*flow_speed
		if a.y-b.y>=maxf(.1,waterfall_drop): waterfalls.append({"from":a,"to":b,"width":(widths[segment]+widths[segment+1])*.5,"drop":a.y-b.y,"flow":direction.normalized()})
func _distance(wet: PackedByteArray,to_water: bool,cancel: Callable) -> PackedFloat32Array:
	var distance:=PackedFloat32Array(); distance.resize(wet.size()); distance.fill(_dimensions.length()*2.); var heap: Array[Vector2]=[]
	for index in wet.size():
		if (wet[index]!=0)==to_water: distance[index]=0.; _push(heap,Vector2(0.,index))
	var iterations:=0
	while not heap.is_empty():
		iterations+=1
		if iterations%128==0 and cancel.is_valid() and cancel.call(): return distance
		var item:=_pop(heap); var index:=int(item.y)
		if item.x>distance[index]+.00001: continue
		var point:=Vector2i(index%_n,index/_n)
		for dz in [-1,0,1]:
			for dx in [-1,0,1]:
				if dx==0 and dz==0: continue
				var next:=point+Vector2i(dx,dz)
				if next.x<0 or next.y<0 or next.x>=_n or next.y>=_n: continue
				var neighbor:=next.x+next.y*_n; var value:=distance[index]+(Vector2(dx,dz)*_spacing).length()
				if value<distance[neighbor]: distance[neighbor]=value; _push(heap,Vector2(value,neighbor))
	return distance
func _build_water(paths: Array[Dictionary],ground: PackedFloat32Array,levels: PackedFloat32Array,kinds: PackedByteArray,cancel: Callable) -> void:
	_vertices=PackedVector3Array(); _normals=PackedVector3Array(); _uv=PackedVector2Array(); _uv2=PackedVector2Array(); _colors=PackedColorArray(); _indices=PackedInt32Array(); _mesh_error=""
	for path in paths:
		var points: PackedVector3Array=path.points; var widths: PackedFloat32Array=path.widths; var distance:=0.
		for index in points.size()-1:
			if cancel.is_valid() and cancel.call(): return
			if _vertices.size()>maxi(1,mesh_vertex_budget): _mesh_error="Water mesh vertex budget exceeded. Reduce path density or terrain water resolution."; return
			var a:=points[index]; var b:=points[index+1]; var ca:=_cell(Vector2(a.x,a.z)); var cb:=_cell(Vector2(b.x,b.z)); var tangent:=b-a; var side:=Vector3(tangent.z,0,-tangent.x).normalized()
			if side.length_squared()<.5: continue
			if kinds[ca]!=0 and kinds[cb]!=0 and absf(a.y-levels[ca])<.05 and absf(b.y-levels[cb])<.05: distance+=tangent.length(); continue
			var normal:=tangent.cross(side).normalized(); var direction:=Vector2(tangent.x,tangent.z).normalized(); var foam:=clampf((a.y-b.y)/maxf(.1,Vector2(tangent.x,tangent.z).length())*.3,0.,1.); var start:=_vertices.size()
			for corner in 6:
				var center:=a if corner<3 else b; var width:=widths[index] if corner<3 else widths[index+1]; var across:=float(corner%3)*.5; var point:=center+side*width*(across-.5); var depth:=maxf(0.,point.y-_sample(ground,Vector2(point.x,point.z))); _vertices.append(point); _normals.append(normal); _uv.append(Vector2(across,distance+(0. if corner<3 else tangent.length()))); _uv2.append(direction); _colors.append(Color(foam,clampf(depth/20.,0.,1.),1.,1.))
			_indices.append_array(PackedInt32Array([start,start+1,start+3,start+1,start+4,start+3,start+1,start+2,start+4,start+2,start+5,start+4])); distance+=tangent.length()
	for z in _n-1:
		if cancel.is_valid() and cancel.call(): return
		if _vertices.size()>maxi(1,mesh_vertex_budget): _mesh_error="Water mesh vertex budget exceeded. Reduce path density or terrain water resolution."; return
		for x in _n-1:
			var a:=x+z*_n; var b:=a+1; var c:=a+_n; var d:=c+1
			for triangle: Array in [[a,b,c],[b,d,c]]:
				var level:=DRY
				for index: int in triangle:
					if kinds[index]!=0: level=maxf(level,levels[index])
				if level<=DRY*.5: continue
				var polygon: Array[Vector3]=[]
				for index: int in triangle: var point:=_point(index); point.y=ground[index]; polygon.append(point)
				polygon=_clip(polygon,level)
				if polygon.size()<3: continue
				var start:=_vertices.size()
				for point in polygon:
					var depth:=maxf(0.,level-point.y); point.y=level; _vertices.append(point); _normals.append(Vector3.UP); _uv.append(Vector2(point.x,point.z)); _uv2.append(wave_direction.normalized()); _colors.append(Color(0.,clampf(depth/20.,0.,1.),0.,1.))
				for index in range(1,polygon.size()-1): _indices.append_array(PackedInt32Array([start,start+index,start+index+1]))
static func _clip(polygon: Array[Vector3],level: float) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	for index in polygon.size():
		var a:=polygon[index]; var b:=polygon[(index+1)%polygon.size()]; var inside_a:=a.y<level; var inside_b:=b.y<level
		if inside_a: result.append(a)
		if inside_a!=inside_b: result.append(a.lerp(b,clampf((level-a.y)/(b.y-a.y),0.,1.)))
	var cleaned: Array[Vector3]=[]
	for point in result:
		if cleaned.is_empty() or cleaned[-1].distance_squared_to(point)>.000000001: cleaned.append(point)
	if cleaned.size()>1 and cleaned[0].distance_squared_to(cleaned[-1])<.000000001: cleaned.remove_at(cleaned.size()-1)
	return cleaned
