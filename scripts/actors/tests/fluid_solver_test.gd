extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func free_motion(_from: Vector3,to: Vector3,_radius: float,_velocity: Vector3) -> Dictionary: return {"position":to,"hits":[]}
func run() -> void:
	var definition:=KiwiFluidDefinition.create(); var actor:=definition.create_actor(); var settings:=KiwiFluidSettings.effective(actor.values)
	var close:=PackedVector3Array([Vector3.ZERO,Vector3(.01,0,0),Vector3(0,.01,0),Vector3(0,0,.01)])
	var dense:={"v":Vector3.ZERO}; KiwiFluidSolver.initialize(dense,settings,close)
	KiwiFluidSolver.step(dense,settings,Vector3.ZERO,Vector3.ZERO,1.0/60,free_motion)
	check(dense.points[0].distance_to(dense.points[1])>.01,"Density projection pushes compressed samples apart")
	var water:={"v":Vector3.ZERO}; var honey:={"v":Vector3.ZERO}
	var pair:=PackedVector3Array([Vector3.ZERO,Vector3(settings.spacing,0,0)])
	KiwiFluidSolver.initialize(water,settings,pair); water.velocities[0]=Vector3.UP; water.velocities[1]=Vector3.DOWN
	KiwiFluidSolver.initialize(honey,settings,pair); honey.velocities=water.velocities.duplicate()
	var sticky:=settings.duplicate(); sticky.merge(KiwiFluidSettings.PRESETS[2],true)
	KiwiFluidSolver.step(water,settings,Vector3.ZERO,Vector3.ZERO,1.0/60,free_motion); KiwiFluidSolver.step(honey,sticky,Vector3.ZERO,Vector3.ZERO,1.0/60,free_motion)
	check(honey.velocities[0].distance_to(honey.velocities[1])<water.velocities[0].distance_to(water.velocities[1]),"Honey damps velocity shear more strongly than water")
	var mesh:=BoxMesh.new(); var data:={"meshes":[{"local":Transform3D.IDENTITY,"surfaces":[mesh.surface_get_arrays(0)]}]}
	var closed:=settings.duplicate(); closed.fluid_shape=3
	check(not KiwiFluidVolume.generate(closed,Transform3D.IDENTITY,data).points.is_empty(),"Closed triangle volumes fill using actual mesh containment")
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	check(not KiwiFluidVolume.generate(closed,Transform3D.IDENTITY,data).error.is_empty(),"Open meshes are rejected rather than leaking silently")
	var reports:=[]; var compute:=KiwiFluidCompute.new()
	check(compute.available(),"Native renderer supports the spatial-hashed GPU PBF path")
	for side in [4,6,8,10]:
		var samples:=PackedVector3Array()
		for x in side:
			for y in side:
				for z in side: samples.append(Vector3(x,y,z)*float(settings.spacing))
		var state:={"v":Vector3.ZERO}; KiwiFluidSolver.initialize(state,settings,samples)
		var started:=Time.get_ticks_usec()
		for i in 3: KiwiFluidSolver.step(state,settings,Vector3.DOWN*9.8,Vector3.ZERO,1.0/60,free_motion,compute)
		var milliseconds:=float(Time.get_ticks_usec()-started)/3000
		var surface:=KiwiFluidSurface.build(state.points,state.fluid_foam,settings)
		var report:={"particles":samples.size(),"step_ms":milliseconds,"surface_ms":float(surface.microseconds)/1000,"grid":surface.get("grid",0),"vertices":surface.get("vertices",0),"state_bytes":var_to_bytes(state).size(),"neighbor_checks":state.fluid_checks}
		reports.append(report); print("FLUID_BENCHMARK ",JSON.stringify(report))
		check(surface.mesh.get_surface_count()==1 and surface.error.is_empty(),"Continuous surface reconstructs %d samples"%samples.size())
	var file:=FileAccess.open("res://.godot/verification/fluid_benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"backend":"GPU PBF + CPU boundary adapter / sparse marching tetrahedra","cpu":OS.get_processor_name(),"renderer":RenderingServer.get_video_adapter_name(),"quality":"Balanced, 3 iterations / 2 substeps","samples":reports},"  ")); file.close(); compute.dispose()
	print("FLUID SOLVER: %d checks, %d failures"%[checks,failures]); quit(failures)
