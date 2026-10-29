extends RefCounted
const NAMES=["Modern City","Suburban Town","Rural Countryside","Medieval Village","Mountain Region","Tropical Island","Fantasy World"]
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
static var pending: Dictionary={}
static func empty(source: Resource) -> bool:
	return source!=null and source.roads.is_empty() and source.settlements.is_empty() and source.forests.is_empty() and source.prop_rules.is_empty() and source.exclusions.is_empty() and source.plot_overrides.is_empty() and not source.regions.any(func(region: Dictionary): return region.get("locked",false))
static func configure(source: Resource,name: String) -> Dictionary:
	if name not in NAMES or not empty(source): return {"error":"Choose an empty world before generating a preset. Existing authored sources are preserved."}
	var next: Resource=source.copy(); var scale:=minf(source.dimensions.x,source.dimensions.y); var profile:="Town"; var style:="Modern"; var terrain_profile:=0; var amplitude:=0.; var forest:=""; var blocks:=3; var radius:=minf(64.,scale*.25); var height:=2; var level:=0.; var rng:=RandomNumberGenerator.new(); rng.seed=int(source.seed); var angle:=rng.randf_range(-.2,.2)
	match name:
		"Modern City": profile="City"; blocks=4; height=6; radius=minf(80.,scale*.3)
		"Suburban Town": forest="Sparse Woodland"; style="Traditional"; terrain_profile=1; amplitude=.6
		"Rural Countryside": profile="Village"; forest="Sparse Woodland"; style="Cottage"; radius=maxf(8.,scale*.1); terrain_profile=1; amplitude=1.5
		"Medieval Village": profile="Village"; forest="Temperate Forest"; style="Medieval"; radius=maxf(8.,scale*.14); terrain_profile=1; amplitude=1.
		"Mountain Region": profile="Village"; forest="Alpine Forest"; style="Cabin"; radius=maxf(8.,scale*.06); terrain_profile=2; amplitude=24.
		"Tropical Island": profile="Village"; forest="Tropical Jungle"; style="Cabin"; radius=maxf(8.,scale*.1); terrain_profile=3; amplitude=14.; level=4.
		"Fantasy World": profile="Town"; forest="Temperate Forest"; style="Fantasy"; terrain_profile=7; amplitude=10.; radius=maxf(8.,scale*.12); blocks=2; height=3; level=3.
	var centers: Array[Vector3]=[Vector3.ZERO]
	if name=="Rural Countryside": centers=[Vector3(-scale*.22,0.,sin(angle)*scale*.15),Vector3(scale*.22,0.,-sin(angle)*scale*.15)]
	var generation:=KiwiTerrainGenerator.preset(terrain_profile)
	for center in centers:
		next=Cities.create(next,center,profile); var index: int=next.settlements.size()-1; var settlement: Dictionary=next.settlements[index]; settlement.id="recipe:"+str(NAMES.find(name))+":settlement:"+str(index); settlement.seed=hash([source.seed,index]); settlement.radius=radius; settlement.blocks=blocks; settlement.height_max=height; settlement.template=Districts.STYLES.apply(settlement.template,style)
		if terrain_profile in [2,3,7]:
			var span:=radius*1.2; var rectangle:=PackedVector2Array([Vector2(center.x-span,center.z-span),Vector2(center.x+span,center.z-span),Vector2(center.x+span,center.z+span),Vector2(center.x-span,center.z+span)])
			generation.layers.append({"id":"recipe:clearing:"+str(index),"type":"Foundation","polygon":rectangle,"plane":Plane(Vector3.UP,level),"feather":maxf(4.,radius*.5),"enabled":true})
		settlement.road_type="Dirt Road" if name in ["Rural Countryside","Medieval Village","Fantasy World"] else ("Forest Track" if name=="Mountain Region" else "Residential Street")
		if name in ["Modern City","Suburban Town"]:
			var central:=radius*.48; var polygon:=PackedVector2Array([Vector2(-central,-central),Vector2(central,-central),Vector2(central,central),Vector2(-central,central)]); var district:=Districts.create("Downtown" if name=="Modern City" else "Park/Green Space",polygon); district.id=settlement.id+":central"; district.seed=source.seed; settlement.districts=[district]
			if name=="Modern City":
				var industrial:=Districts.create("Industrial",PackedVector2Array([Vector2(-radius,radius*.5),Vector2(radius,radius*.5),Vector2(radius,radius),Vector2(-radius,radius)])); industrial.id=settlement.id+":industrial"; settlement.districts.append(industrial)
	if not forest.is_empty():
		next=Forests.create(next,Vector3.ZERO,forest); next.forests[0].id="recipe:forest"; next.forests[0].budget=750; next.forests[0].density=.5 if forest!="Sparse Woodland" else .3
	for kind in (["Park bench","Street lamp"] if name in ["Modern City","Suburban Town"] else ["Rock cluster"]):
		next=preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd").add(next,kind); next.prop_rules[-1].id="recipe:prop:"+str(next.prop_rules.size()-1); next.prop_rules[-1].budget=200
	var water: KiwiTerrainHydrology
	if name=="Tropical Island": water=KiwiTerrainHydrology.new(); water.automatic_rivers=false; water.automatic_lakes=false; water.ocean_enabled=true; water.sea_level=0.; water.water_color=Color(.08,.65,.72,.92)
	return {"error":"","source":next,"terrain_settings":{"generation":generation,"dimensions":next.dimensions,"amplitude":amplitude,"base_height":0.,"frequency":1./maxf(24.,scale*.25),"seed":source.seed,"hydrology":water}}
static func cancel(session: KiwiModelSession) -> void:
	var state: Dictionary=pending.get(session.get_instance_id(),{})
	if state.is_empty(): return
	state.cancelled=true; state.job.cancel()
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree; var success:=true
	while pending.has(session.get_instance_id()):
		var state: Dictionary=pending[session.get_instance_id()]
		while pending.get(session.get_instance_id(),{})==state: await tree.process_frame
		success=success and bool(state.get("success",false))
	return success
static func request(workspace: Control,id: String,name: String) -> void:
	var session: KiwiEnvironmentSession=workspace.session
	if pending.has(session.get_instance_id()): workspace.status.text="Finish or cancel the current world preset first."; return
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(session) or not is_instance_valid(workspace) or workspace.session!=session: return
	var authored:=Worlds.source(session.document.component(id))
	if authored==null or authored.terrain_id.is_empty() or authored.terrain_id!=authored.owned_terrain_id: workspace.status.text="Presets need an empty world with its own terrain; external terrain is preserved."; return
	var recipe:=configure(authored,name)
	if not str(recipe.error).is_empty(): workspace.status.text=recipe.error; return
	if session.pending_source_cancel.is_valid() or not session._gesture.is_empty(): workspace.status.text="Finish the current edit before generating a world preset."; return
	var ground:=session.environment().terrain(authored.terrain_id)
	if ground==null: workspace.status.text="The world's owned terrain is missing."; return
	if not session.document.editable_component(session.document.component(id)) or not session.document.editable_component(session.document.component(authored.terrain_id)): workspace.status.text="Unlock the world and its terrain before generating a preset."; return
	var tree:=workspace.get_tree(); var terrain_job:=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd").new(); var state: Dictionary={"job":terrain_job,"document":session.document,"revision":session.revision,"success":false,"cancelled":false,"was_dirty":session.dirty}; pending[session.get_instance_id()]=state; session.pending_source_cancel=cancel.bind(session); session.dirty=true; workspace.set_meta("world_recipe_job",terrain_job); terrain_job.start(ground,recipe.terrain_settings,true); workspace.status.text="Generating "+name+" terrain…"
	while terrain_job.task_id>=0 and not terrain_job.complete():
		if not is_instance_valid(workspace) or not workspace.is_inside_tree() or workspace.session!=session or session.document!=state.document or session.revision!=state.revision: cancel(session)
		await tree.process_frame
	terrain_job.collect(); var error:=str(terrain_job.error); var generated: Dictionary={}
	if not state.cancelled and error.is_empty():
		var staged:=KiwiEnvironmentSession.new(); staged.document=session.environment().snapshot(); staged.environment().component_settings[authored.terrain_id].terrain=terrain_job.terrain; staged.document.component(authored.terrain_id).mesh=terrain_job.mesh; var desired: Resource=recipe.source
		var field:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").capture(staged,id,desired); error=str(field.error)
		if error.is_empty():
			desired.terrain_field=field.field; desired.terrain_dependency_key=int(field.field.key); error=preload("res://Workspaces/EnvironmentWorkspace/world/world_occupancy.gd").capture(session,id,desired)
			if error.is_empty():
				var job:=preload("res://Workspaces/EnvironmentWorkspace/world/world_recipe_job.gd").new(); state.job=job; workspace.set_meta("world_recipe_job",job); workspace.status.text="Placing settlements and generating "+name+"…"; job.start(desired)
				while job.task>=0 and not job.complete():
					if not is_instance_valid(workspace) or not workspace.is_inside_tree() or workspace.session!=session or session.document!=state.document or session.revision!=state.revision: cancel(session)
					await tree.process_frame
				generated=job.collect()
				if not state.cancelled and not generated.get("cancelled",false) and generated.get("document")!=null and generated.errors.is_empty():
					desired=job.authored; generated.signature=desired.signature(); generated.document.component(id).parameters.world_recipe=name; generated.terrain_result={"id":authored.terrain_id,"terrain":terrain_job.terrain,"mesh":terrain_job.mesh}; session.pending_source_cancel=Callable(); var applied:=Worlds.update(session,id,desired,"Generate "+name,generated); generated=applied; state.success=applied.errors.is_empty()
	pending.erase(session.get_instance_id())
	if session.pending_source_cancel==cancel.bind(session): session.pending_source_cancel=Callable()
	if not state.success and session.document==state.document and session.revision==state.revision: session.dirty=state.was_dirty
	if not is_instance_valid(workspace) or not workspace.is_inside_tree() or workspace.session!=session: return
	workspace.remove_meta("world_recipe_job")
	if state.cancelled: workspace.status.text="World preset canceled; the previous terrain and world are intact."
	elif not error.is_empty(): workspace.status.text=error
	elif not generated.get("errors",PackedStringArray()).is_empty(): workspace.status.text=generated.errors[0]
	else: workspace.status.text=" · ".join(generated.get("warnings",PackedStringArray())) if not generated.get("warnings",PackedStringArray()).is_empty() else name+" generated"; workspace.canvas.frame(true)

