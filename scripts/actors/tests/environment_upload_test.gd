extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=257; terrain.amplitude=3.; var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var runtime:=KiwiEnvironmentRuntime.new(); runtime.progressive=true; runtime.upload_budget_usec=1; root.add_child(runtime)
	var started:=Time.get_ticks_usec(); runtime.configure(document); var setup_ms:=float(Time.get_ticks_usec()-started)/1000.
	check(runtime.pending_chunks.size()==64 and runtime.chunks_rebuilt==0,"Large preview queues chunk uploads without synchronously constructing every GPU mesh")
	runtime._process(0.); check(runtime.pending_chunks.size()==63 and runtime.chunks_rebuilt==1,"A small upload budget processes only one chunk per scheduling pass")
	var peak:=0.; var passes:=0
	while not runtime.pending_chunks.is_empty() and passes<100:
		started=Time.get_ticks_usec(); runtime._process(0.); peak=maxf(peak,float(Time.get_ticks_usec()-started)/1000.); passes+=1
	check(runtime.pending_chunks.is_empty() and runtime.nodes[item.id].get_child_count()==64,"Progressive preview eventually commits every native mesh and collider")
	terrain.sculpt(Vector2(-10,-10),1.,1.,1.,0); runtime.sync(); var other:=KiwiEnvironmentDocument.new(); var other_item:=other.add_terrain(); runtime.configure(other)
	while not runtime.pending_chunks.is_empty(): runtime._process(0.)
	check(runtime.nodes.has(other_item.id) and not runtime.nodes.has(item.id),"Switching source documents discards pending uploads for the old terrain")
	print("ENVIRONMENT UPLOAD setup_ms=",setup_ms," max_single_chunk_pass_ms=",peak," chunks=64")
	runtime.queue_free(); await process_frame; print("ENVIRONMENT UPLOAD: %d checks, %d failures"%[checks,failures]); quit(failures)
