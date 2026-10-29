extends "res://scripts/actors/tests/environment_generation_test.gd"
func run() -> void:
	var source:=KiwiEnvironmentTerrain.new(); var job:=Job.new(); job.start(source,{"resolution":1025,"dimensions":Vector2(4096,4096),"amplitude":20.},false); var deadline:=Time.get_ticks_msec()+45000
	while not job.complete() and Time.get_ticks_msec()<deadline: await process_frame
	if not job.complete(): job.cancel()
	job.collect(); var terrain: KiwiEnvironmentTerrain=job.terrain
	check(job.error.is_empty() and not job.cancelled() and terrain.resolution==1025 and terrain.validate().is_empty(),"A cancelable worker generates a real 1025-square source for a four-kilometer terrain")
	if job.mesh==null: quit(failures); return
	check(job.mesh.vertices.size()==129*129 and job.mesh.faces.size()==128*128*2,"Large terrain keeps a bounded authoring proxy while its source retains all million height samples")
	check(terrain.chunk_keys.size()==1024 and terrain.chunk_keys_stamp!=0,"Worker precomputes and stores native chunk signatures rather than hashing a million samples in the UI")
	var coordinate:=Vector2i(16,16); var key:=terrain.chunk_geometry_key(coordinate); var corner:=terrain.chunk_geometry_key(Vector2i.ZERO); var index:=512+512*1025; terrain.apply_samples({index:5.}); terrain.prepare_geometry_keys()
	check(terrain.chunk_geometry_key(coordinate)!=key and terrain.chunk_geometry_key(Vector2i.ZERO)==corner,"Editing a large terrain invalidates affected chunk signatures and preserves remote chunks")
	var session:=KiwiEnvironmentSession.new(); var item:=session.environment().add_terrain(terrain); session.patch_editable(item.id,{index:5.}); check(absf(item.mesh.vertices[64+64*129].y-terrain.height(512,512))<.00001,"Large source edits update their corresponding bounded authoring proxy")
	var path:="user://large-terrain.res"; ResourceSaver.save(terrain,path,ResourceSaver.FLAG_COMPRESS); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentTerrain; loaded.prepare(); check(loaded.chunk_keys.size()==1024 and loaded.chunk_keys_stamp==terrain.chunk_keys_stamp and loaded.chunk_geometry_key(coordinate)==terrain.chunk_geometry_key(coordinate),"Compressed native resources preserve large source edits and reusable native chunk signatures")
	if DisplayServer.get_name()!="headless":
		var runtime:=KiwiEnvironmentRuntime.new(); runtime.progressive=true; runtime.upload_budget_usec=1; root.add_child(runtime); var start:=Time.get_ticks_usec(); runtime.configure(session.environment()); var setup:=float(Time.get_ticks_usec()-start)/1000.; runtime._process(0.); check(runtime.pending_chunks.size()==1023 and runtime.chunks_rebuilt==1,"A real renderer progressively uploads a large terrain one native chunk at a time"); print("LARGE TERRAIN queue_ms=",setup); runtime.queue_free(); await process_frame
	print("LARGE TERRAIN generate_ms=",job.elapsed_ms," source_samples=",1025*1025," proxy_vertices=",job.mesh.vertices.size()); session._undo.clear(); session._redo.clear(); DirAccess.remove_absolute(path); print("TERRAIN LARGE WORLD: %d checks, %d failures"%[checks,failures]); quit(failures)
