extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Cities.create(Worlds.source(world),Vector3.ZERO); source=Forests.create(source,Vector3.ZERO,"Conifer Forest"); source.forests[0].budget=30; var result:=await Edit.request(session,id,source); var building: KiwiModelComponent; var meshes: Dictionary={}
	for item in session.document.components:
		if item.parameters.has("architecture_source"): building=item
		if item.parameters.get("world_generated",false) and not str(item.parameters.get("world_key","")).begins_with(":forest:"): meshes[item.id]=item.mesh
	check(result.errors.is_empty() and building!=null and session.environment().validate().is_empty(),"A town and native conifer forest generate together with shared terrain and development masks")
	# A forest edit must not even rebuild this locally edited building source.
	var building_id:=building.id; var edited: Resource=building.parameters.architecture_source; edited.baseboard_height=.12; var original_key:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(edited); source=Worlds.source(session.document.component(id)).copy(); source.forests[0].density=.5; result=await Edit.request(session,id,source,"Thin forest")
	var retained:=true
	for identity in meshes: retained=retained and session.document.component(identity)!=null and session.document.component(identity).mesh==meshes[identity]
	check(result.errors.is_empty() and result.get("development_reused",false) and retained,"Forest-only edits reuse existing street/building geometry instead of regenerating the settlement")
	check(preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(session.document.component(building_id).parameters.architecture_source)==original_key,"Unrelated local building-source edits survive forest changes")
	var saved:=ResourceSaver.save(session.environment(),"user://world_incremental.res"); var reopened:=ResourceLoader.load("user://world_incremental.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; session.document=reopened; source=Worlds.source(reopened.component(id)).copy(); source.forests[0].patch_scale=32.; result=await Edit.request(session,id,source)
	check(saved==OK and result.errors.is_empty() and result.get("development_reused",false),"Incremental dependency signatures remain valid after native save/reopen")
	source=Worlds.source(session.document.component(id)).copy(); source.settlements[0].radius+=1.; result=await Edit.request(session,id,source); check(not result.errors.is_empty() and str(result.errors[0]).contains("local source edits"),"A real development change still protects locally edited building sources")
	print("WORLD INCREMENTAL: %d checks, %d failures"%[checks,failures]); quit(failures)
