extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var signatures:={}; var started:=Time.get_ticks_usec()
	for profile in KiwiTerrainGenerator.PROFILES.size():
		var terrain:=KiwiEnvironmentTerrain.new(); terrain.generation=KiwiTerrainGenerator.preset(profile); terrain.amplitude=20.; terrain.seed=47; terrain.prepare(); var a:=terrain._base.duplicate(); var copy:=terrain.duplicate(true) as KiwiEnvironmentTerrain; copy.prepare()
		check(a==copy._base,"%s generates deterministic physical heights from the saved source"%KiwiTerrainGenerator.PROFILES[profile]); signatures[hash(a)]=true
		if profile==0: check(a[0]==0. and Array(a).max()==0.,"Flat profile creates actual flat geometry")
		if profile==3: check(terrain.sample(Vector2.ZERO).height>terrain.sample(Vector2(15,15)).height+5.,"Island profile lowers the coastline relative to its interior")
	check(signatures.size()>=9,"Terrain profiles produce distinct height geometry instead of renamed appearance presets")
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.generation=KiwiTerrainGenerator.preset(9); terrain.amplitude=10.; var noise_results:={}
	for kind in 5: terrain.generation.noise_type=kind; terrain.prepare(); noise_results[hash(terrain._base)]=true
	check(noise_results.size()==5,"Simplex, Perlin, ridged, cellular and warped modes produce different sampled terrain")
	terrain.amplitude=0.; terrain.generation=KiwiTerrainGenerator.preset(0)
	for kind in KiwiTerrainGenerator.LANDFORMS:
		terrain.generation.layers=[{"type":kind,"center":Vector2(-2,1),"width":5.,"length":12.,"height":8.,"direction":25.,"sharpness":2.}]; terrain.prepare(); var changed:=false
		for height in terrain._base:
			if absf(height)>.001: changed=true; break
		check(changed,"%s modifies the actual terrain elevation"%kind)
	terrain.generation.layers=[{"type":"Valley","center":Vector2.ZERO,"width":4.,"length":15.,"height":6.,"mask":{"center":Vector2.ZERO,"radius":5.,"falloff":.3}}]; terrain.prepare()
	check(terrain.sample(Vector2.ZERO).height<-5. and absf(terrain.sample(Vector2(0,10)).height)<.00001,"Landform masks carve inside the selected region and preserve terrain outside it")
	terrain.generation.layers=[{"type":"Hill","width":8.,"length":8.,"height":5.,"blend":"replace"},{"type":"Hill","width":8.,"length":8.,"height":2.,"blend":"add"}]; terrain.prepare(); var ordered: float=terrain.sample(Vector2.ZERO).height; terrain.generation.layers.reverse(); terrain.prepare()
	check(absf(ordered-7.)<.001 and absf(terrain.sample(Vector2.ZERO).height-5.)<.001,"Reordering geological layers changes their evaluated geometry in authored order")
	var session:=KiwiEnvironmentSession.new(); var item:=session.add_terrain(); session.begin_terrain(item.id); session.sculpt(Vector2.ZERO,2.,1.,1.,0); session.finish_terrain(); var sculpt:=session.environment().terrain(item.id).edits.duplicate(); var source:=KiwiTerrainGenerator.preset(2); session.regenerate_terrain(item.id,{"generation":source,"amplitude":10.})
	check(session.environment().terrain(item.id).edits==sculpt,"Changing a generation profile preserves separate authored sculpt edits")
	session.undo(); check(session.environment().terrain(item.id).generation==null and session.environment().terrain(item.id).edits==sculpt,"Profile changes undo to the original source and sculpt data")
	session.redo(); check(session.environment().terrain(item.id).generation.profile==2,"Profile changes redo their procedural source")
	var snapshot:=session.environment().snapshot() as KiwiEnvironmentDocument; snapshot.terrain(item.id).generation.sharpness=7.; check(session.environment().terrain(item.id).generation.sharpness!=7.,"Environment history snapshots isolate editable generator settings")
	var path:="user://terrain-generator.tres"; ResourceSaver.save(session.environment(),path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; loaded.terrain(item.id).prepare()
	session.environment().terrain(item.id).prepare(); check(loaded.terrain(item.id)._base==session.environment().terrain(item.id)._base and loaded.terrain(item.id).edits==sculpt,"Saved terrain reopens with matching generated and sculpted heights")
	print("TERRAIN GENERATION profile_and_landform_suite_ms=",float(Time.get_ticks_usec()-started)/1000.); DirAccess.remove_absolute(path); session._undo.clear(); session._redo.clear(); print("TERRAIN GENERATION: %d checks, %d failures"%[checks,failures]); quit(failures)
