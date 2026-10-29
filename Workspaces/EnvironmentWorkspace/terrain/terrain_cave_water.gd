extends RefCounted
## Bounded hydrostatic connectivity through the real cave air field. This is
## reservoir flooding, not a second dynamic liquid/particle solver.
const DRY:=-1.0e20
static func generate(terrain: Resource,cancel: Callable=Callable()) -> Dictionary:
	var sources: Array[KiwiTerrainCave]=[]; var bounds:=AABB(); var first:=true
	for cave: KiwiTerrainCave in terrain.caves:
		if cave==null or not cave.enabled: continue
		cave.prepare(); sources.append(cave); bounds=cave.bounds() if first else bounds.merge(cave.bounds()); first=false
	if first: return {}
	var n: int=terrain.resolution; var levels: PackedFloat32Array=terrain.water_data.get("levels",PackedFloat32Array()); var depths: PackedFloat32Array=terrain.water_data.get("depth",PackedFloat32Array()); var highest:=DRY
	for index in levels.size():
		if depths[index]>.0001: highest=maxf(highest,levels[index])
	if highest<=DRY*.5: return {}
	var dimensions: Vector2=terrain.dimensions; var dxz:=dimensions/(n-1); var start:=Vector2i(((Vector2(bounds.position.x,bounds.position.z)/dimensions+Vector2.ONE*.5)*(n-1)).floor()).max(Vector2i.ZERO); var end:=Vector2i(((Vector2(bounds.end.x,bounds.end.z)/dimensions+Vector2.ONE*.5)*(n-1)).ceil()).min(Vector2i.ONE*(n-1)); var dy:=maxf(.1,float(terrain.voxel_height)); var lower:=floorf(bounds.position.y/dy)*dy-dy; var upper:=minf(highest+dy,bounds.end.y+dy)
	if end.x<=start.x or end.y<=start.y or upper<=lower: return {}
	lower=highest-ceilf((highest-bounds.position.y)/dy)*dy-dy
	var size:=Vector3i(end.x-start.x+1,ceili((upper-lower)/dy)+1,end.y-start.y+1); var count:=size.x*size.y*size.z
	if count>int(terrain.voxel_cell_budget): return {"error":"Cave water volume budget exceeded. Increase voxel height, reduce cave extent or increase the voxel budget."}
	var origin:=Vector3((float(start.x)/(n-1)-.5)*dimensions.x,lower,(float(start.y)/(n-1)-.5)*dimensions.y); var spacing:=Vector3(dxz.x,dy,dxz.y); var air:=PackedByteArray(); air.resize(count); var heads:=PackedFloat32Array(); heads.resize(count); heads.fill(DRY); var heap: Array[Vector2]=[]
	for z in size.z:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for x in size.x:
			var source_index:=start.x+x+(start.y+z)*n; var ground: float=terrain.height(start.x+x,start.y+z)
			for y in size.y:
				var index:=x+y*size.x+z*size.x*size.y; var point:=origin+Vector3(x,y,z)*spacing; var inside:=point.y>ground+.00001 or _void(point,sources)<-.00001
				if index%128==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true}
				if not inside: continue
				air[index]=1
				if point.y>ground+.00001 and depths[source_index]>.0001 and point.y<=levels[source_index]+.00001:
					heads[index]=levels[source_index]; KiwiTerrainHydrology._push(heap,Vector2(-heads[index],index))
	var visited:=PackedByteArray(); visited.resize(count); var iterations:=0
	while not heap.is_empty():
		iterations+=1
		if iterations%128==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true}
		var entry:=KiwiTerrainHydrology._pop(heap); var index:=int(entry.y)
		if visited[index]!=0: continue
		visited[index]=1; var x:=index%size.x; var y: int=(index/size.x)%size.y; var z: int=index/(size.x*size.y); var head:=heads[index]
		for offset: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
			var p:=Vector3i(x,y,z)+offset
			if p.x<0 or p.y<0 or p.z<0 or p.x>=size.x or p.y>=size.y or p.z>=size.z or origin.y+p.y*dy>head+.00001: continue
			var neighbor:=p.x+p.y*size.x+p.z*size.x*size.y
			if air[neighbor]==0 or visited[neighbor]!=0 or heads[neighbor]>=head-.00001: continue
			heads[neighbor]=head; KiwiTerrainHydrology._push(heap,Vector2(-head,neighbor))
	var columns:=PackedFloat32Array(); columns.resize(size.x*size.z); columns.fill(DRY); var floors:=PackedFloat32Array(); floors.resize(size.x*size.z); floors.fill(INF)
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var index:=x+y*size.x+z*size.x*size.y
				if heads[index]<=DRY*.5: continue
				columns[x+z*size.x]=maxf(columns[x+z*size.x],heads[index]); floors[x+z*size.x]=minf(floors[x+z*size.x],origin.y+y*dy-dy*.5)
	var mesh: Dictionary=terrain.water_data.get("mesh",{}).duplicate(true)
	if mesh.is_empty(): mesh={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"uv2":PackedVector2Array(),"colors":PackedColorArray(),"indices":PackedInt32Array()}
	for z in size.z-1:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for x in size.x-1:
			for triangle: Array in [[Vector2i(x,z),Vector2i(x+1,z),Vector2i(x,z+1)],[Vector2i(x+1,z),Vector2i(x+1,z+1),Vector2i(x,z+1)]]:
				var head:=DRY
				for p: Vector2i in triangle: head=maxf(head,columns[p.x+p.y*size.x])
				if head<=DRY*.5: continue
				var polygon: Array[Vector3]=[]; var field:=PackedFloat32Array(); var bed:=head
				for p: Vector2i in triangle:
					var point:=Vector3(origin.x+p.x*spacing.x,head,origin.z+p.y*spacing.z); var ground: float=terrain.height(start.x+p.x,start.y+p.y); polygon.append(point); var y:=clampi(floori((head-origin.y)/dy),0,size.y-1); var connected:=heads[p.x+y*size.x+p.y*size.x*size.y]>=head-.001; field.append(minf(-_void(point,sources),ground-head) if connected else -dy); bed=minf(bed,floors[p.x+p.y*size.x])
				polygon=_clip(polygon,field)
				if polygon.size()<3: continue
				if mesh.vertices.size()+polygon.size()>terrain.hydrology.mesh_vertex_budget: return {"error":"Cave water mesh budget exceeded."}
				var base: int=mesh.vertices.size()
				for point in polygon: mesh.vertices.append(point); mesh.normals.append(Vector3.UP); mesh.uv.append(Vector2(point.x,point.z)); mesh.uv2.append(terrain.hydrology.wave_direction); mesh.colors.append(Color(0.,clampf((head-bed)/20.,0.,1.),0.,1.))
				for index in range(1,polygon.size()-1): mesh.indices.append_array(PackedInt32Array([base,base+index,base+index+1]))
	return {"origin":origin,"spacing":spacing,"size":size,"heads":heads,"floors":floors,"mesh":mesh,"voxels":count}
static func query(terrain: Resource,point: Vector3) -> Dictionary:
	var field: Dictionary=terrain.water_data.get("cave_volume",{})
	if field.is_empty(): return {}
	var origin: Vector3=field.origin; var spacing: Vector3=field.spacing; var size: Vector3i=field.size; var p:=Vector3i(((point-origin)/spacing).round())
	if p.x<0 or p.y<0 or p.z<0 or p.x>=size.x or p.y>=size.y or p.z>=size.z: return {}
	var sources: Array[KiwiTerrainCave]=[]
	for cave: KiwiTerrainCave in terrain.caves:
		if cave!=null and cave.enabled:
			if cave._noise==null: cave.prepare()
			sources.append(cave)
	if _void(point,sources)>=0.: return {}
	var heads: PackedFloat32Array=field.heads; var head:=heads[p.x+p.y*size.x+p.z*size.x*size.y]
	if head<=DRY*.5: return {}
	var y:=p.y
	while y>0 and heads[p.x+(y-1)*size.x+p.z*size.x*size.y]>DRY*.5: y-=1
	var bottom: float=origin.y+(y-.5)*spacing.y
	return {"surface":Vector3(point.x,head,point.z),"depth":head-bottom,"flow":Vector3.ZERO,"inside":point.y<=head and point.y>=bottom,"bottom":bottom,"cave":true}
static func _void(point: Vector3,sources: Array[KiwiTerrainCave]) -> float:
	var result:=INF
	for cave in sources: result=minf(result,cave.distance(point))
	return result
static func _clip(points: Array[Vector3],field: PackedFloat32Array) -> Array[Vector3]:
	var output: Array[Vector3]=[]
	for index in points.size():
		var next: int=(index+1)%points.size(); var a:=field[index]; var b:=field[next]
		if a>0.: output.append(points[index])
		if (a>0.)!=(b>0.): output.append(points[index].lerp(points[next],a/(a-b)))
	return output
