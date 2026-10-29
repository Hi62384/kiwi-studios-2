extends "res://scripts/actors/tests/surface_growth_test.gd"
const Spatial=preload("res://Workspaces/EnvironmentWorkspace/world/world_spatial_index.gd")
func run() -> void:
	var spatial:=Spatial.new(); var rng:=RandomNumberGenerator.new(); rng.seed=1987; var source: Array[Rect2]=[]
	for index in 1000:
		var bounds:=Rect2(Vector2(rng.randf_range(-1000,1000),rng.randf_range(-1000,1000)),Vector2(rng.randf_range(1,200),rng.randf_range(1,200))); source.append(bounds); spatial.add(bounds,index)
	var matches:=true; var checks_run:=0; var started:=Time.get_ticks_usec()
	for index in 100:
		var bounds:=Rect2(Vector2(rng.randf_range(-1000,1000),rng.randf_range(-1000,1000)),Vector2(50,70)); var expected: Array=[]
		for record in source.size():
			if source[record].intersects(bounds,true): expected.append(record)
		var actual:=spatial.query(bounds); actual.sort(); matches=matches and actual==expected; checks_run+=1
	check(matches and checks_run==100,"Indexed footprint queries exactly match brute-force overlap checks across negative coordinates and bin boundaries")
	var before:=spatial.bins.size(); spatial.add(Rect2(-10000,-10000,20000,20000),"large"); var found:=spatial.query(Rect2(-2,-2,4,4)); check(spatial.bins.size()==before and found.has("large"),"World-sized masks use the bounded large-footprint list instead of allocating millions of cells")
	var wide:=spatial.query(Rect2(-10000,-10000,20000,20000)); check(wide.size()==1001,"A large query returns each cached footprint exactly once")
	var edge:=Spatial.new(); edge.add(Rect2(-64,-64,64,64),"edge"); check(edge.query(Rect2(0,0,1,1)).has("edge"),"Boundary-touching candidates reach exact geometry validation rather than being lost in the broad phase")
	print("WORLD SPATIAL measured 100 indexed/brute comparisons ms=",float(Time.get_ticks_usec()-started)/1000.," bins=",spatial.bins.size()); print("WORLD SPATIAL: %d checks, %d failures"%[checks,failures]); quit(failures)
