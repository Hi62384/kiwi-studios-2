extends "res://scripts/actors/tests/surface_growth_test.gd"
const Edit=preload("res://Workspaces/ModelWorkspace/natural_edit.gd")
func settle(workspace: Control) -> void:
	for frame in 600:
		if workspace.get_meta("natural_edit",{}).is_empty(): return
		await process_frame
	check(false,"Natural source editing completes within bounded frame wait")
func run() -> void:
	var workspace:=KiwiModelWorkspace.new(); root.add_child(workspace); await process_frame; var source:=workspace.session.add("Tree / Oak",{"levels":1}); var id:=source.id; var original:=source.mesh.vertices.duplicate(); var history:=workspace.session._undo.size()
	Edit.request(workspace,id,"height",10.,false); Edit.request(workspace,id,"height",12.,false)
	check(source.parameters.height==6. and source.mesh.vertices==original,"Pending source workers do not mutate live authored geometry")
	Edit.finish(workspace); await settle(workspace)
	check(workspace.session.document.component(id).parameters.height==12. and workspace.session._undo.size()==history+1,"Latest superseding source result commits one gesture")
	workspace.session.undo(); check(workspace.session.document.component(id).mesh.vertices==original,"Asynchronous source change undoes exactly")
	workspace.session.redo(); check(workspace.session.document.component(id).parameters.height==12.,"Asynchronous source change redoes exact parameters")
	var before:=workspace.session.document.component(id).mesh.vertices.duplicate(); Edit.request(workspace,id,"seed",93,false); Edit.cancel(workspace)
	for i in 20: await process_frame
	check(workspace.session.document.component(id).mesh.vertices==before,"Cancelled worker cannot install late geometry")
	Edit.request(workspace,id,"seed",94,true); workspace.session.undo(); await settle(workspace)
	check(workspace.session.document.component(id).parameters.height==12.,"Undo cancels a pending worker without undoing another completed action")
	var job:=preload("res://Workspaces/ModelWorkspace/natural_job.gd").new(); job.cancel(); job.start("Tree / Oak",{})
	while not job.complete(): await process_frame
	var cancelled: Dictionary=job.collect(); check(cancelled.get("cancelled",false) and cancelled.mesh==null,"Worker cancellation returns no partial mesh")
	workspace.session.dirty=false; Edit.request(workspace,id,"seed",95,false); Edit.cancel(workspace)
	check(not workspace.session.dirty,"Cancelling a pending edit preserves the prior saved status")
	workspace.session.document.workspace_state.natural_folds={"preserved":true}; Edit.request(workspace,id,"height",11.,true)
	var saved: Error=await workspace.save_to("user://async_natural.res"); var loaded:=ResourceLoader.load("user://async_natural.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(saved==OK and loaded.component(id).parameters.height==11.,"Save waits for the latest source result before writing")
	check(loaded.workspace_state.get("natural_folds",{}).get("preserved",false),"Model saving preserves source-inspector fold state")
	workspace.queue_free(); await process_frame
	print("NATURAL ASYNC: %d checks, %d failures"%[checks,failures]); quit(failures)
