extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var controller:=KiwiTimelinePhysics.new(); var model:=ActorTimeline.new(); controller._model=model; controller.world.create()
	var source:=registry.get_definition(&"basic_shape").create_actor(); source.values.physics={"enabled":true,"gravity":0.0,"damping":0.0,"angular_damping":0.0,"friction":0.0,"bounce":.2}; model.actors.append(source); model.clips.append(ActorClip.create(source)); controller.prototypes[source.id]={"actor":source,"clip":model.clips[0],"geometry":{"meshes":[]}}
	var fragments:=[]
	for sign_value in [-1,1]: fragments.append({"id":source.id+":fragment:"+str(sign_value),"mesh":KiwiModelPrimitives.box(Vector3.ONE*.5),"pose":Transform3D(Basis.IDENTITY,Vector3(sign_value,0,0)),"v":Vector3(-sign_value*4,0,0),"w":Vector3.ZERO,"mass":1.0,"sleep":0.0})
	controller.states[source.id]={"pose":Transform3D.IDENTITY,"type":0,"initialized":true,"active":true,"v":Vector3.ZERO,"destruction_detached":true,"destruction_fragments":fragments,"destruction_geometry":{"materials":[],"rows":[],"key":0}}
	controller.destruction.sync_actor_world(controller,source.id,controller.states[source.id],0)
	for i in 30: controller.debris.step(controller,float(i)/60,1.0/60)
	check(fragments[0].pose.origin.x<fragments[1].pose.origin.x,"Opposing physical fragment hulls cannot pass through one another")
	check((fragments[0].v+fragments[1].v).length()<.001,"Fragment contacts exchange equal and opposite linear impulses")
	check(fragments[0].v.x<3.5 and fragments[1].v.x>-3.5,"Mutual contacts change fragment motion rather than only drawing different transforms")
	var target:=registry.get_definition(&"basic_shape").create_actor(); target.values.physics={"enabled":true,"mass":2.0}; model.actors.append(target); model.clips.append(ActorClip.create(target)); controller.prototypes[target.id]={"actor":target,"clip":model.clips[-1],"geometry":{"meshes":[]}}; controller.states[target.id]={"pose":Transform3D.IDENTITY,"type":0,"initialized":true,"active":true,"responds":true,"v":Vector3.ZERO,"w":Vector3.ZERO,"sleep":0.0}; var box:=BoxShape3D.new(); box.size=Vector3.ONE; controller.world.add(target.id,box,Transform3D.IDENTITY,1,1); controller.world.place(target.id,Transform3D.IDENTITY)
	for fragment: Dictionary in fragments: controller.world.remove(fragment.id)
	fragments.resize(1); fragments[0].pose=Transform3D(Basis.IDENTITY,Vector3(-1.5,0,0)); fragments[0].v=Vector3(6,0,0); fragments[0].w=Vector3.ZERO; controller.destruction.sync_actor_world(controller,source.id,controller.states[source.id],0)
	var blocked:=controller.world.move(fragments[0].id,fragments[0].pose,Vector3(3,0,0)); var ignored:=controller.world.move(fragments[0].id,fragments[0].pose,Vector3(3,0,0),[target.id])
	check(not blocked.hits.is_empty() and ignored.hits.is_empty() and ignored.travel==Vector3(3,0,0),"Native collision exclusions actually remove joined/ignored bodies from query contacts")
	for i in 20: controller.debris.step(controller,float(i+31)/60,1.0/60)
	check(controller.states[target.id].v.x>.1,"Debris collision impulses push a compatible dynamic rigid actor")
	controller.dispose(); print("DEBRIS COLLISIONS: %d checks, %d failures"%[checks,failures]); quit(failures)
