extends RefCounted
## Shared 3D cave suitability for materials, vegetation and natural props.
static func generate(terrain: Resource,cancel: Callable=Callable()) -> Dictionary:
	if terrain.biomes==null: return {}
	var biomes:=terrain.biomes as KiwiTerrainBiomes; var noises:=biomes.noise_fields(terrain.seed,"cave")
	if noises.is_empty(): return {}
	var sources: Array[KiwiTerrainCave]=[]; var bounds:=AABB(); var first:=true
	for cave: KiwiTerrainCave in terrain.caves:
		if cave==null or not cave.enabled: continue
		cave.prepare(); sources.append(cave); bounds=cave.bounds() if first else bounds.merge(cave.bounds()); first=false
	if first: return {}
	var n: int=terrain.resolution; var dimensions: Vector2=terrain.dimensions; var step:=maxf(.1,float(terrain.voxel_height)); var start:=Vector2i(((Vector2(bounds.position.x,bounds.position.z)/dimensions+Vector2.ONE*.5)*(n-1)).floor()).max(Vector2i.ZERO); var end:=Vector2i(((Vector2(bounds.end.x,bounds.end.z)/dimensions+Vector2.ONE*.5)*(n-1)).ceil()).min(Vector2i.ONE*(n-1)); var origin:=Vector3((float(start.x)/(n-1)-.5)*dimensions.x,floorf(bounds.position.y/step)*step,(float(start.y)/(n-1)-.5)*dimensions.y); var spacing:=Vector3(dimensions.x/(n-1),step,dimensions.y/(n-1)); var size:=Vector3i(end.x-start.x+1,ceili((bounds.end.y-origin.y)/step)+1,end.y-start.y+1)
	if size.x<2 or size.y<2 or size.z<2: return {}
	var count:=size.x*size.y*size.z
	if count>terrain.voxel_cell_budget: return {"error":"Cave biome field budget exceeded. Reduce cave extent or increase voxel size/budget."}
	var fields:={}; var presence:=PackedByteArray(); presence.resize(count)
	for id: String in noises: var values:=PackedFloat32Array(); values.resize(count); fields[id]=values
	var directional:=false
	for definition: Dictionary in biomes.definitions:
		if noises.has(str(definition.id)) and definition.get("surface_type","any")!="any": directional=true
	for z in size.z:
		for x in size.x:
			var source_index:=start.x+x+(start.y+z)*n; var ground: float=terrain.height(start.x+x,start.y+z); var humidity: float=terrain.biome_data.humidity[source_index] if terrain.biome_data.has("humidity") else biomes.base_humidity; var temperature: float=terrain.biome_data.temperature[source_index] if terrain.biome_data.has("temperature") else biomes.sea_temperature
			for y in size.y:
				var index:=x+y*size.x+z*size.x*size.y
				if index%128==0 and cancel.is_valid() and cancel.call(): return {"cancelled":true}
				var point:=origin+Vector3(x,y,z)*spacing
				if point.y>ground+step*.1 or _void(point,sources)>maxf(maxf(spacing.x,spacing.z),spacing.y)*.75: continue
				presence[index]=1; var depth:=maxf(0.,ground-point.y); var wet: Dictionary=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").query(terrain,point); var normal:=Vector3.UP
				if directional or terrain.water_data.has("cave_volume"):
					var h:=minf(.2,step*.3); normal=-Vector3(_void(point+Vector3(h,0,0),sources)-_void(point-Vector3(h,0,0),sources),_void(point+Vector3(0,h,0),sources)-_void(point-Vector3(0,h,0),sources),_void(point+Vector3(0,0,h),sources)-_void(point-Vector3(0,0,h),sources)).normalized()
				if wet.is_empty() and terrain.water_data.has("cave_volume"): wet=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").query(terrain,point+normal*step*.4)
				var submersion: float=(wet.surface as Vector3).y-point.y if not wet.is_empty() else -10000.; var moisture:=maxf(humidity,.92 if not wet.is_empty() else .55)
				var surface_type:="floor" if normal.y>.5 else ("ceiling" if normal.y<-.5 else "wall"); var climate:=biomes.sea_temperature*.75+temperature*.25+depth*.025; var values:=biomes._weights_sample(Vector2(point.x,point.z),point.y,rad_to_deg(acos(clampf(normal.y,-1.,1.))),climate,moisture,0.,0.,source_index,n,noises,{"domain":"cave","geology":terrain.geology,"cave_depth":depth,"submersion":submersion,"surface_type":surface_type,"noise_position":point})
				for id: String in values: fields[id][index]=values[id]
	return {"origin":origin,"spacing":spacing,"size":size,"weights":fields,"presence":presence,"voxels":count}
static func query(terrain: Resource,point: Vector3) -> Dictionary:
	var data: Dictionary=terrain.cave_biome_data
	if data.is_empty(): return {}
	var size: Vector3i=data.size; var p: Vector3=(point-(data.origin as Vector3))/(data.spacing as Vector3)
	if p.x<0 or p.y<0 or p.z<0 or p.x>size.x-1 or p.y>size.y-1 or p.z>size.z-1: return {}
	var cell:=Vector3i(p.floor()).min(size-Vector3i.ONE*2); var f:=p-Vector3(cell); var result:={}; var total:=0.
	for id: String in data.weights:
		var values: PackedFloat32Array=data.weights[id]; var value:=0.
		for z in 2:
			for y in 2:
				for x in 2: value+=values[cell.x+x+(cell.y+y)*size.x+(cell.z+z)*size.x*size.y]*(f.x if x==1 else 1.-f.x)*(f.y if y==1 else 1.-f.y)*(f.z if z==1 else 1.-f.z)
		result[id]=value; total+=value
	if total<=.000001: return {}
	for id: String in result: result[id]/=total
	return result
static func _void(point: Vector3,sources: Array[KiwiTerrainCave]) -> float:
	var result:=INF
	for cave in sources: result=minf(result,cave.distance(point))
	return result
