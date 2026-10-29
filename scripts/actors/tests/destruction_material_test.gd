extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func response(material: ActorObjectData,energy: float,cell: Dictionary={},normal: Vector3=Vector3.UP) -> Dictionary:
	return KiwiDestructionMaterial.response(material,{"energy":energy,"normal":normal,"local_point":Vector3.ZERO},cell,.3)
func run() -> void:
	var glass:=KiwiDestructionMaterial.preset(0); var steel:=KiwiDestructionMaterial.preset(1); var wood:=KiwiDestructionMaterial.preset(3); var stone:=KiwiDestructionMaterial.preset(4); var concrete:=KiwiDestructionMaterial.preset(5); var rubber:=KiwiDestructionMaterial.preset(8)
	var g:=response(glass,12); var s:=response(steel,12); var w:=response(wood,12); var r:=response(rubber,12); var st:=response(stone,12); var co:=response(concrete,12)
	check(g.get("type",-1)==2 and s.get("type",-1)==9,"Identical energy shatters brittle glass but dents ductile steel")
	check(r.get("type",-1)==9 and r.get("elastic",false),"Rubber responds with recoverable deformation instead of brittle fracture")
	check(st.get("pieces",0)!=co.get("pieces",0) and st.get("irregularity",0)!=co.get("irregularity",0),"Stone and concrete use distinct chunk distributions and split-plane variation")
	var strong:=glass.copy_object(); strong.values.strength=300.
	check(response(strong,12).get("type",-1)!=2,"Greater physical strength raises the failure threshold")
	var tough:=glass.copy_object(); tough.values.toughness=300.
	check(response(tough,12).get("type",-1)!=2,"Greater toughness resists complete crack propagation and separation")
	var cell:={"damage":0.0}; var first:=response(glass,.8,cell); var last:={}
	for i in 20: last=response(glass,.8,cell)
	check(first.get("type",-1)!=2 and last.get("type",-1)==2,"Repeated lower-energy impacts accumulate local damage until fracture")
	var untouched:={"damage":0.0}; response(glass,.01,untouched)
	check(untouched.damage==0.,"Damage on one region does not weaken unrelated regions")
	var along:=response(wood,2,{},Vector3.UP); var across:=response(wood,2,{},Vector3.RIGHT)
	check(along.get("type",-1)!=across.get("type",-1) or along.get("amount",0)!=across.get("amount",0),"Wood grain direction changes its energy threshold and response")
	var cube:=KiwiModelPrimitives.box(Vector3.ONE)
	var a:=KiwiDestructionGeometry.evaluate(cube,{"impact":g},1); var b:=KiwiDestructionGeometry.evaluate(cube,{"impact":w},1)
	check(a.error.is_empty() and b.error.is_empty() and hash(a.parts[0].vertices)!=hash(b.parts[0].vertices),"Material parameters change actual deterministic fracture geometry")
	var seeded:=g.duplicate(true); seeded.seed+=1; var changed:=KiwiDestructionGeometry.evaluate(cube,{"impact":seeded},1)
	check(changed.error.is_empty() and changed.parts[0].vertices!=a.parts[0].vertices,"Changing the fracture seed changes real valid pieces")
	var advanced:=steel.copy_object(); advanced.values.advanced=true; advanced.values.yield_energy=35.; advanced.values.fracture_energy=500.; response(advanced,20)
	check(advanced.values.yield_energy==35. and advanced.values.fracture_energy==500.,"Explicit advanced energies are never overwritten by the basic recipe")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var actor:=registry.get_definition(&"basic_shape").create_actor()
	actor.values.destruction_enabled=true; actor.values.destruction_material=ActorObjectReference.from_object(steel)
	var region:=registry.get_object_definition(&"destruction_region").create_object(); region.values.material=ActorObjectReference.from_object(glass); region.values.center=Vector3.LEFT; region.values.radius=.3; actor.values.destruction_region=ActorObjectReference.from_object(region)
	check(KiwiDestructionMaterial.resolve(actor.values,Vector3.LEFT)==glass and KiwiDestructionMaterial.resolve(actor.values,Vector3.RIGHT)==steel,"Explicit local regions override actor/component material only at the impacted location")
	var visual:=registry.get_object_definition(&"material").create_object(); visual.values.damage_material=ActorObjectReference.from_object(wood); actor.values.material=ActorObjectReference.from_object(visual); actor.values.destruction_material=null; actor.values.destruction_region=null
	check(KiwiDestructionMaterial.resolve(actor.values)==wood,"Visual materials can explicitly associate a separate physical damage material")
	var path:="user://damage_material_"+ActorData.new_id()+".tres"; ResourceSaver.save(wood,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(loaded.values.material_id==wood.values.material_id and loaded.values.anisotropy==wood.values.anisotropy,"Custom physical material identity and anisotropy survive resource saving")
	var store:=KiwiClipboardStore.new("user://damage_clipboard_"+ActorData.new_id()); var id:=store.save(wood,"Wood physics"); var portable:=ResourceLoader.load(store.entry_path(id),"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(portable!=null and portable.type_id==&"destruction_material", "Destruction materials reuse Super Clipboard storage")
	var model:=ActorTimeline.new(); model.create_actor(registry.get_definition(&"basic_shape"),0,actor.values); var data:=model.selected_actor(); var before:=KiwiPhysicsSettings.fingerprint(model)
	visual.set_value(&"tint",Color.RED); check(KiwiPhysicsSettings.fingerprint(model)==before,"Appearance-only changes do not invalidate physical material damage")
	var linked:=KiwiDestructionMaterial.resolve(data.values); linked.set_value(&"strength",800.); check(KiwiPhysicsSettings.fingerprint(model)!=before,"Shared physical-material edits invalidate dependent timeline caches")
	DirAccess.remove_absolute(path)
	print("DESTRUCTION MATERIALS: %d checks, %d failures"%[checks,failures]); quit(failures)
