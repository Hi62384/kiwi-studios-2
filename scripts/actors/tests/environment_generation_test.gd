extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Job=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd")
func run() -> void:
	var workspace:=Workspace.new(); root.add_child(workspace)
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(); workspace.open_source(document)
	await process_frame
	var terrain:=workspace.session.environment().terrain(item.id); var signature:=terrain.signature()
	workspace._regenerate_terrain(item.id,{"resolution":129,"amplitude":4.,"seed":81})
	check(terrain.signature()==signature,"Background generation leaves authored terrain unchanged until commit")
	await drain(workspace)
	var generated:=workspace.session.environment().terrain(item.id)
	check(generated.resolution==129 and generated.seed==81 and generated.amplitude==4. and workspace.session.document.component(item.id).mesh.vertices.size()==129*129,"Worker results commit complete terrain and editable geometry together")
	workspace.session.undo(); check(workspace.session.environment().terrain(item.id).signature()==signature,"Background generation undoes as one authored operation")
	workspace.session.redo(); check(workspace.session.environment().terrain(item.id).seed==81,"Background generation redoes exactly")
	workspace._regenerate_terrain(item.id,{"resolution":257,"seed":82}); workspace._cancel_generation(); await drain(workspace)
	check(workspace.session.environment().terrain(item.id).seed==81,"Canceled generation never replaces authored terrain")
	workspace._regenerate_terrain(item.id,{"resolution":257,"seed":83}); var current:=workspace.session.environment().terrain(item.id); current.apply_samples({0:1.}); await drain(workspace)
	check(workspace.session.environment().terrain(item.id)==current and current.seed==81 and current.edits[0]==1.,"Late worker output is discarded after a newer sculpt edit")
	workspace._regenerate_terrain(item.id,{"resolution":257,"seed":84}); var other:=KiwiEnvironmentDocument.new(); other.add_terrain(); workspace.open_source(other); await drain(workspace)
	check(workspace.session.environment().environment_id==other.environment_id,"Switching documents cancels work without leaking results into the new tab")
	var job:=Job.new(); job.start(terrain,{"resolution":257},false); job.cancel(); job.collect(); check(job.cancelled(),"Worker shutdown joins safely after cancellation")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame
	print("ENVIRONMENT GENERATION: %d checks, %d failures"%[checks,failures]); quit(failures)
func drain(workspace: Control) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not workspace._generation_jobs.is_empty() and Time.get_ticks_msec()<deadline:
		workspace._poll_generation(); await process_frame
	check(workspace._generation_jobs.is_empty(),"Generation finishes within the bounded test window")
