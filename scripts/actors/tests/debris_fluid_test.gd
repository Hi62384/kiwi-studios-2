extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func fixture(gravity: float=0) -> Dictionary:
	var controller:=KiwiTimelinePhysics.new(); var model:=ActorTimeline.new(); controller._model=model
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var actor:=registry.get_definition(&"basic_shape").create_actor({&"physics":{"enabled":true,"gravity":gravity,"damping":0.0,"angular_damping":0.0},&"debris_enabled":true}); var fluid:=KiwiFluidDefinition.create().create_actor({&"fluid_spacing":.2,&"fluid_quality":1})
	actor.values[&"physics"]={"enabled":true,"gravity":gravity,"damping":0.0,"angular_damping":0.0}
	model.actors.assign([actor,fluid]); model.clips.assign([ActorClip.create(actor),ActorClip.create(fluid)])
	for i in model.actors.size(): controller.prototypes[model.actors[i].id]={"actor":model.actors[i],"clip":model.clips[i],"geometry":{"meshes":[],"bounds":AABB(-Vector3.ONE*.05,Vector3.ONE*.1)}}
	var state:={"type":6,"active":true,"initialized":true,"pose":Transform3D.IDENTITY,"v":Vector3.ZERO}; var points:=PackedVector3Array()
	for x in range(-2,3):
		for y in range(-2,3):
			for z in range(-2,3): points.append(Vector3(x,y,z)*.2)
	KiwiFluidSolver.initialize(state,KiwiFluidSettings.effective(fluid.values),points)
	var fragment:={"id":actor.id+":fragment:0","pose":Transform3D(Basis.IDENTITY,Vector3(.03,.01,.02)),"v":Vector3.DOWN*2,"w":Vector3.ZERO,"mass":.1,"mesh":KiwiModelPrimitives.box(Vector3.ONE*.1),"sleep":0.0}
	controller.states[fluid.id]=state; controller.states[actor.id]={"active":true,"initialized":true,"type":0,"pose":Transform3D.IDENTITY,"v":Vector3.ZERO,"destruction_fragments":[fragment]}; return {"controller":controller,"fragment":fragment,"fluid":state}
func momentum(data: Dictionary) -> Vector3:
	var sum: Vector3=data.fragment.v*float(data.fragment.mass)
	for i in data.fluid.points.size(): sum+=data.fluid.velocities[i]*float(data.fluid.fluid_masses[i])
	return sum
func run() -> void:
	var data:=fixture(); var initial:=momentum(data); data.controller.debris.step(data.controller,0,1.0/60)
	print("FLUID MOMENTUM before=",initial," after=",momentum(data)," v=",data.fragment.v," total=",data.fluid.velocities[62])
	check(data.fragment.v.y>-2,"Kernel-sampled fluid drag slows actual rigid fragment inventory")
	check(momentum(data).distance_to(initial)<.00001,"Fragment drag exchanges equal and opposite momentum with fluid samples")
	var a:=fixture(9.8); var b:=fixture(9.8); a.fragment.mass=.1; b.fragment.mass=10.; a.fragment.v=Vector3.ZERO; b.fragment.v=Vector3.ZERO; a.controller.debris.step(a.controller,0,1.0/60); b.controller.debris.step(b.controller,0,1.0/60)
	check(a.fragment.v.y>b.fragment.v.y,"Displaced geometry volume and fragment mass affect buoyancy")
	for item in [data,a,b]: item.controller.dispose()
	print("DEBRIS FLUID: %d checks, %d failures"%[checks,failures]); quit(failures)
