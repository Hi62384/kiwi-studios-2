extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.amplitude=0.; terrain.base_height=4.; terrain.prepare(); var cave:=KiwiTerrainCave.new(); cave.radius=2.; cave.roughness=0.; cave.radius_variation=0.; cave.paths=[PackedVector3Array([Vector3(-6,0,0),Vector3(6,0,0)])]; terrain.caves=[cave]
	var source:=KiwiEnvironmentScatter.new(); source.palette=[{"source":"decoration.res"}]; source.budget=20; source.minimum_distance=.1; source.density=.1; source.slope_range=Vector2(0,90)
	for domain in [1,2,3]:
		source.surface_domain=domain; var result:=source.generate(terrain); var attached: bool=result.count>0; var orientation:=true
		for batch: Array in result.batches.values():
			for pose: Transform3D in batch:
				attached=attached and absf(cave.distance(pose.origin))<.005
				orientation=orientation and (pose.basis.y.y>.5 if domain==1 else (pose.basis.y.y<-.5 if domain==2 else absf(pose.basis.y.y)<.5))
		check(attached,"Cave domain %d instances touch actual air/solid boundary"%domain)
		check(orientation,"Cave domain %d aligns to inward surface normal"%domain)
		check(result.batches==source.generate(terrain).batches,"Cave domain %d is deterministic"%domain)
	print("NATURAL CAVE SCATTER: %d checks, %d failures"%[checks,failures]); quit(failures)
