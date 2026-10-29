extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.amplitude=0.; terrain.prepare(); var source:=KiwiEnvironmentScatter.new(); source.palette=[{"source":"tree.tres"}]; source.slope_range=Vector2(0,90); source.density=.2; source.minimum_distance=.5
	var original:=source.generate(terrain); var identity: String=original.placements.keys()[0]; source.overrides[identity]={"deleted":true}; var deleted:=source.generate(terrain)
	check(not deleted.placements.has(identity),"Per-instance deletion survives regeneration")
	var same:=0
	for id: String in original.placements:
		if id!=identity and deleted.placements.has(id) and deleted.placements[id]==original.placements[id]: same+=1
	check(same>=original.count-2,"Removing one candidate does not reshuffle surviving instances")
	source.overrides.clear(); var pose: Transform3D=original.placements[identity].transform; pose.origin.y+=3.; source.overrides[identity]={"transform":pose}; var moved:=source.generate(terrain)
	check(moved.placements[identity].transform==pose,"Explicit transform override survives procedural evaluation")
	source.overrides.clear(); source.cluster_count=3; source.cluster_radius=2.; var clustered:=source.generate(terrain)
	check(clustered.count>0 and clustered.batches==source.generate(terrain).batches,"Cluster distributions are real and repeatable")
	var path:="user://stable_scatter.res"; ResourceSaver.save(source,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentScatter
	check(loaded.generate(terrain).placements==clustered.placements,"Candidate identities persist across save and reopen")
	print("NATURAL SCATTER STABILITY: %d checks, %d failures"%[checks,failures]); quit(failures)
