extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func fixture(density: float=1800.0) -> Dictionary:
	var controller:=KiwiTimelinePhysics.new(); controller._model=ActorTimeline.new()
	var liquid:=KiwiFluidDefinition.create().create_actor({&"fluid_spacing":.2,&"fluid_quality":1})
	var powder:=KiwiPowderDefinition.create().create_actor({&"powder_density":density,&"powder_radius":.05})
	controller._model.actors.assign([liquid,powder]); var lc:=ActorClip.create(liquid); var pc:=ActorClip.create(powder); controller._model.clips.assign([lc,pc])
	controller.prototypes[liquid.id]={"actor":liquid,"clip":lc,"geometry":{"meshes":[]}}; controller.prototypes[powder.id]={"actor":powder,"clip":pc,"geometry":{"meshes":[]}}
	var fluid_state:={"v":Vector3.ZERO,"type":6,"active":true,"initialized":true,"pose":Transform3D.IDENTITY}
	var points:=PackedVector3Array()
	for x in range(-2,3):
		for y in range(-2,3):
			for z in range(-2,3): points.append(Vector3(x,y,z)*.2)
	KiwiFluidSolver.initialize(fluid_state,KiwiFluidSettings.effective(liquid.values),points)
	var grain_state:={"v":Vector3.ZERO,"type":7,"active":true,"initialized":true,"pose":Transform3D.IDENTITY}; KiwiPowderSource.initialize(grain_state); grain_state.powder_time=0.0
	KiwiPowderSource.append(grain_state,Vector3(.03,.01,.02),Vector3.DOWN*2,powder.values,Transform3D.IDENTITY,0,0)
	controller.states[liquid.id]=fluid_state; controller.states[powder.id]=grain_state
	var batch:={"id":powder.id,"state":grain_state,"settings":KiwiPowderSettings.effective(powder.values),"config":KiwiPhysicsSettings.authored(powder),"h":1.0/60,"moving":true,"gravity":Vector3.DOWN*9.8}
	return {"controller":controller,"powder":powder,"liquid":liquid,"batch":batch,"grain":grain_state,"fluid":fluid_state}
func momentum(data: Dictionary) -> Vector3:
	var total: Vector3=data.grain.velocities[0]*float(data.grain.powder_masses[0])
	for i in data.fluid.points.size(): total+=data.fluid.velocities[i]*float(data.fluid.fluid_masses[i])
	return total
func run() -> void:
	var data:=fixture(); var before:=momentum(data); data.batch.gravity=Vector3.ZERO
	KiwiPowderFluid.forces(data.controller,[data.batch],0)
	check(data.grain.velocities[0].y>-2 and data.grain.velocities[0].y<0,"Liquid drag slows a descending grain")
	check(momentum(data).distance_to(before)<.00001,"Two-way fluid drag exchanges approximately equal and opposite momentum")
	var response:=0.0
	for v: Vector3 in data.fluid.velocities: response+=v.length()
	check(response>0,"Fluid velocity responds to granular drag, not just the grain")
	var dry:=fixture(1800); var buoyant:=fixture(500)
	for item in [dry,buoyant]: item.grain.velocities[0]=Vector3.ZERO; KiwiPowderFluid.forces(item.controller,[item.batch],0)
	check(buoyant.grain.velocities[0].y>dry.grain.velocities[0].y*2,"Buoyancy scales with displaced volume and grain density")
	var moving:=fixture()
	for i in moving.fluid.velocities.size(): moving.fluid.velocities[i]=Vector3.RIGHT*5
	moving.grain.velocities[0]=Vector3.ZERO; KiwiPowderFluid.forces(moving.controller,[moving.batch],0)
	check(moving.grain.velocities[0].x>.1,"Moving liquid transfers flow momentum to grains")
	var old_points: PackedVector3Array=moving.fluid.points.duplicate(); var old_grain: Vector3=moving.grain.points[0]
	KiwiPowderFluid.contacts(moving.controller,[moving.batch],0)
	check(moving.fluid.points!=old_points and moving.grain.points[0]!=old_grain,"Mass-weighted granular-fluid contacts displace both liquid and grains")
	var old_velocity: Vector3=moving.grain.velocities[0]; moving.batch.config.mask=2; KiwiPowderFluid.forces(moving.controller,[moving.batch],0)
	check(moving.grain.velocities[0]==old_velocity,"Fluid coupling respects collision layer/mask filtering")
	for item in [data,dry,buoyant,moving]: item.controller.dispose()
	print("POWDER FLUID: %d checks, %d failures"%[checks,failures]); quit(failures)
