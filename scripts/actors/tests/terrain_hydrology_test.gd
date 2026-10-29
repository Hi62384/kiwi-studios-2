extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var source:=PackedFloat32Array(); var n:=33; source.resize(n*n)
	for z in n:
		for x in n: source[x+z*n]=8.-z*.4+pow(float(x)-16.,2.)*.025
	var original:=source.duplicate(); var water:=KiwiTerrainHydrology.new(); water.catchment_threshold=8.; water.rainfall_variation=0.; water.automatic_lakes=false; var first:=water.generate(source,n,Vector2(32,32),41); var repeated:=water.generate(source,n,Vector2(32,32),41)
	check(not first.cancelled and source==original and first.paths.size()>0,"Drainage generation finds actual downhill river paths while preserving its source heights")
	check(first.delta==repeated.delta and first.paths==repeated.paths,"River routing, widths and channel carving are deterministic")
	var root_area:=0.; var acyclic:=true
	for index in n*n:
		if first.downstream[index]<0: root_area+=first.accumulation[index]
		var cursor:=index; var visited:={}
		while cursor>=0:
			if visited.has(cursor): acyclic=false; break
			visited[cursor]=true; cursor=first.downstream[cursor]
	check(acyclic and absf(root_area-1024.)<.01,"Priority-flood routing is acyclic and conserves physical catchment area at its outlets")
	var downhill:=true; var carved:=false; var variable_width:=false
	for path in first.paths:
		for index in path.points.size()-1: downhill=downhill and path.points[index].y>=path.points[index+1].y-.00001
		var widths: PackedFloat32Array=path.widths
		for width in widths: variable_width=variable_width or absf(width-widths[0])>.01
	for value in first.delta: carved=carved or value<-.1
	check(downhill and variable_width,"Generated rivers flow downhill and widen according to real accumulated catchment")
	check(carved and first.mesh.vertices.size()>0 and first.mesh.indices.size()>0,"Rivers lower terrain geometry and create actual water surfaces")
	var wet:=false; var moisture:=false
	for index in n*n: wet=wet or first.depth[index]>.1; moisture=moisture or first.moisture[index]>.5
	check(wet and moisture and first.shore_distance.size()==n*n,"Water generation provides depth, shoreline and moisture fields for downstream systems")
	var basin:=PackedFloat32Array(); basin.resize(n*n)
	for z in n:
		for x in n: basin[x+z*n]=Vector2(x-16,z-16).length_squared()*.02
	water.automatic_rivers=false; water.automatic_lakes=true; var lake:=water.generate(basin,n,Vector2(32,32),1)
	check(lake.depth[16+16*n]>4. and lake.levels[16+16*n]>5. and lake.mesh.vertices.size()>0,"Basin drainage creates a lake at its actual spill level with depth and geometry")
	var coast:=PackedFloat32Array(); coast.resize(n*n)
	for z in n:
		for x in n: coast[x+z*n]=float(x-16)*.125
	water.automatic_lakes=false; water.ocean_enabled=true; water.sea_level=0.; var ocean:=water.generate(coast,n,Vector2(32,32),1); var clipped: bool=ocean.mesh.vertices.size()>0
	for point: Vector3 in ocean.mesh.vertices: clipped=clipped and point.x<=.00001 and absf(point.y)<.00001
	check(clipped and ocean.depth[4+16*n]>1.,"Ocean geometry clips to the actual coastline instead of covering dry terrain with a decorative plane")
	check(water.generate(coast,n,Vector2(32,32),1,func(): return true).get("cancelled",false),"Hydrology generation supports cancellation before publishing partial output")
	print("TERRAIN HYDROLOGY river_paths=",first.paths.size()," river_vertices=",first.mesh.vertices.size()," river_ms=",first.milliseconds," lake_ms=",lake.milliseconds," ocean_ms=",ocean.milliseconds); print("TERRAIN HYDROLOGY: %d checks, %d failures"%[checks,failures]); quit(failures)
