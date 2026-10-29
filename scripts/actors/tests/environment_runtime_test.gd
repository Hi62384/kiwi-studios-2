extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var source:=KiwiModelSession.new(); source.add("Box",{"size":Vector3.ONE}); var path:="user://environment-scatter-model.tres"; ResourceSaver.save(source.document,path)
	var env:=KiwiEnvironmentDocument.new(); var terrain_item:=env.add_terrain(); var terrain:=env.terrain(terrain_item.id); var layer:=env.add_group("Trees"); layer.parent_id=terrain_item.id; var scatter:=KiwiEnvironmentScatter.new(); scatter.terrain_id=terrain_item.id; scatter.palette=[{"source":path,"weight":1.}]; scatter.region=Rect2(-15,-15,30,30); scatter.density=2.; scatter.minimum_distance=.4; scatter.budget=1000; env.component_settings[layer.id]={"kind":"scatter","scatter":scatter}
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); root.add_child(view); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); var started:=Time.get_ticks_usec(); runtime.configure(env); var milliseconds:=float(Time.get_ticks_usec()-started)/1000.
	check(runtime.chunks_rebuilt==4 and runtime.nodes[terrain_item.id].get_child_count()==4,"Environment runtime builds bounded native terrain chunks")
	check(runtime.instances==1000 and runtime.find_children("*","MultiMeshInstance3D",true,false).size()==1,"A thousand repeated models render through one native MultiMesh")
	check(env.components.size()==2 and runtime.get_child_count()==2,"Generated repeated objects do not become independent authored components or actors")
	var first:=runtime.nodes[terrain_item.id].get_node("Chunk_0_0") as MeshInstance3D; var original:=first.mesh; terrain.sculpt(Vector2(-10,-10),1.,1.,1.,0); runtime.sync()
	check(runtime.chunks_rebuilt==1 and first.mesh!=original,"A small sculpt rebuilds only its intersecting chunk and collision shape")
	var collider:=first.get_node("Collision/Shape") as CollisionShape3D
	check(collider.shape is ConcavePolygonShape3D and collider.shape.get_faces()==first.mesh.get_faces(),"Chunk collision uses the actual updated terrain triangles")
	var second:=KiwiEnvironmentRuntime.new(); view.add_child(second); second.configure(env)
	check(second.nodes[terrain_item.id].get_node("Chunk_0_0").mesh==first.mesh,"Multiple environment instances share unchanged terrain mesh resources")
	scatter.collisions=true; scatter.budget=10; runtime.sync(); var collision_proxy:=runtime.nodes[layer.id].get_node_or_null("ScatterCollision") as MeshInstance3D
	check(collision_proxy!=null and not collision_proxy.visible and collision_proxy.get_node("Collision").get_child(0).shape.get_faces().size()==10*36,"Collision-enabled scatter builds one native aggregate from the actual repeated cube triangles")
	var captured:=KiwiPhysicsGeometry.meshes(runtime,{})
	check(captured.has(collision_proxy),"Kiwi's existing offline physics discovers the aggregate scatter collider")
	scatter.collisions=false; runtime.sync(); check(not runtime.nodes[layer.id].has_node("ScatterCollision") and KiwiPhysicsGeometry.meshes(runtime,{}).size()==4,"Decorative scatter removes its collider and stays excluded from offline collision capture")
	print("ENVIRONMENT RUNTIME first_1000_instances_ms=",milliseconds," node_count=",runtime.find_children("*","Node",true,false).size())
	view.queue_free(); await process_frame; source._undo.clear(); source._redo.clear(); DirAccess.remove_absolute(path); print("ENVIRONMENT RUNTIME: %d checks, %d failures"%[checks,failures]); quit(failures)
