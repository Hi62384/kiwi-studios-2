extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(2,1,2)}); KiwiSurfaceGrowth.add(session,1); var data:=session.primary().growth; data.settings.density=1000; data.settings.quality=0; session.document.prepare_growth(); KiwiSurfaceGrowth.render(data)
	var tool:=KiwiGroomTool.new(); tool.radius=.15; tool.through=true; tool.tool="Comb"; var costs:=[]; var touched:=[]; var chunks:=[]
	for i in 4:
		var center:=Vector3(-.5+float(i)*.25,0,0); var start:=Time.get_ticks_usec(); var before:=data.chunk_builds; var count:=tool.apply_at(data,center,Vector3(.1,0,0),Vector3.UP); KiwiSurfaceGrowth.render(data); costs.append((Time.get_ticks_usec()-start)/1000.0); touched.append(count); chunks.append(data.chunk_builds-before)
	print("DENSE_GROOM roots=",data.roots.size()," touched=",touched," full_apply_render_ms=",costs," rebuilt_chunks=",chunks," cached_chunks=",data.chunks.size())
	var ok:=true
	for count: int in chunks: ok=ok and count<data.chunks.size()/2
	if not ok: push_error("Local grooming unexpectedly rebuilt the whole groom")
	quit(0 if ok else 1)
