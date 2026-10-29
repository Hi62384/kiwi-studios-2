extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry)
	for count in [16,64,128]:
		var controller:=KiwiTimelinePhysics.new(); var model:=ActorTimeline.new(); controller._model=model
		for i in count:
			var actor:=registry.get_definition(&"basic_shape").create_actor({&"structure_enabled":true,&"structure_role":1 if i==0 else 0,&"position":Vector3(i,0,0)}); var clip:=ActorClip.create(actor); model.actors.append(actor); model.clips.append(clip)
			controller.prototypes[actor.id]={"actor":actor,"clip":clip,"geometry":{"meshes":[],"bounds":AABB(-Vector3.ONE*.5,Vector3.ONE)}}; controller.states[actor.id]={"active":true,"type":0,"initialized":true,"pose":Transform3D(Basis.IDENTITY,Vector3(i,0,0)),"v":Vector3.ZERO,"w":Vector3.ZERO,"sleep":0.0}
			if i>0:
				var previous: ActorData=model.actors[i-1]; var link:=KiwiStructure.connection(actor.id,Vector3.RIGHT*.5,Vector3.LEFT*.5); link.prevent_failure=true; previous.values.structure_connections={"joint":link}
		controller.structure.step(controller,0,0); var elapsed:=0
		for frame in 5:
			for state: Dictionary in controller.states.values(): state.v+=Vector3.DOWN*9.8/60; state.pose.origin+=state.v/60
			var start:=Time.get_ticks_usec(); controller.structure.step(controller,float(frame+1)/60,1.0/60); elapsed+=Time.get_ticks_usec()-start
		print("STRUCTURAL BENCH elements=",count," joints=",count-1," iterations=12 mean_ms=",elapsed/5000.0," graph_rebuilds=",controller.structure.graph_builds)
		if controller.structure.graph_builds!=1: push_error("Stable topology unnecessarily rebuilt islands"); quit(1); return
		controller.dispose()
	print("STRUCTURAL PERFORMANCE: 3 bounded-size scenarios passed"); quit(0)
