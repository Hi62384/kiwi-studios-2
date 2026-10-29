extends "res://scripts/actors/tests/surface_growth_test.gd"
func vertices(mesh: Mesh) -> int:
	var result:=0
	for i in mesh.get_surface_count(): result+=mesh.surface_get_array_len(i)
	return result
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(2,1,2)}); KiwiSurfaceGrowth.add(session,1); var component:=session.primary(); component.growth.settings.density=500.; component.growth.settings.quality=2; session.document.prepare_growth()
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,1,2); camera.current=true
	var instance:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(instance); instance.configure(component,true); instance.update_growth()
	var count:=vertices(instance.mesh); var roots:=instance.data.roots.duplicate(true); var start:=Time.get_ticks_usec(); camera.position.z=30.; instance.update_growth(); var far_cost:=Time.get_ticks_usec()-start; var reduced:=vertices(instance.mesh)
	check(reduced<count/3 and reduced>0,"Far detail reduces real geometric strand and subdivision counts")
	check(instance.data.roots==roots and component.growth.lod_upper==1.,"LOD preserves authored roots and does not mutate the source or another instance")
	var builds:=instance.data.chunk_builds; instance.update_growth(); check(instance.data.chunk_builds==builds,"An unchanged camera reuses its LOD geometry")
	viewport.set_meta("kiwi_final_growth",true); instance.update_growth(); var final_count:=vertices(instance.mesh)
	check(final_count>count and instance.data.render_final,"Final render restores full authored coverage and final subdivisions")
	viewport.remove_meta("kiwi_final_growth"); camera.position.z=2.; instance.update_growth(); check(vertices(instance.mesh)==count,"Leaving final render restores ordinary viewport quality")
	instance.data.appearance.mode=1; instance.update_growth(); check(vertices(instance.mesh)<count and instance.data.roots==roots,"Stylized representation simplifies the same groom without rebuilding root data")
	print("GROWTH_LOD roots=",roots.size()," near_vertices=",count," far_vertices=",reduced," final_vertices=",final_count," far_rebuild_ms=",far_cost/1000.)
	viewport.queue_free(); await process_frame; print("GROWTH LOD: %d checks, %d failures"%[checks,failures]); quit(failures)
