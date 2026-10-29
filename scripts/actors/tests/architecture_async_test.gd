extends "res://scripts/actors/tests/surface_growth_test.gd"
const Edit=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
func send(session: KiwiModelSession,id: String,source: Resource,label: String="Async building") -> void:
	await Edit.request(session,id,source,label)
func run() -> void:
	var workspace:=KiwiModelWorkspace.new(); root.add_child(workspace); await process_frame; var session:=workspace.session; var building:=Buildings.add(session,Vector3.ZERO,3); var id:=building.id; var original: Resource=Buildings.source(building); var history:=session._undo.size()
	var first: Resource=Source.copy(original); first.roof_pitch=42.; send(session,id,first)
	var next: Resource=Source.copy(Edit.source(session,id)); next.wall_thickness=.3; send(session,id,next)
	check(Buildings.source(session.document.component(id)).roof_pitch==30.,"Pending workers keep the live document unchanged")
	await Edit.flush(session); var source:=Buildings.source(session.document.component(id))
	check(source.roof_pitch==42. and source.wall_thickness==.3 and session._undo.size()==history+1,"Superseded source edits merge into one completed history action")
	session.undo(); check(Buildings.source(session.document.component(id)).roof_pitch==30.,"Asynchronous generation undoes through normal history")
	session.redo(); check(Buildings.source(session.document.component(id)).wall_thickness==.3,"Asynchronous generation redoes exact authored settings")
	next=Source.copy(Edit.source(session,id)); next.roof_pitch=51.; send(session,id,next); session.undo(); await Edit.flush(session)
	check(Buildings.source(session.document.component(id)).roof_pitch==42. and session._undo.size()==history+1,"Undo cancels pending generation without undoing the preceding completed action")
	session.dirty=false; next=Source.copy(Edit.source(session,id)); next.roof_pitch=53.; send(session,id,next); Edit.cancel(session)
	for i in 10: await process_frame
	check(not session.dirty and Buildings.source(session.document.component(id)).roof_pitch==42.,"Cancellation restores saved status and prevents late result installation")
	next=Source.copy(Edit.source(session,id)); next.roof_pitch=54.; send(session,id,next); var saved: Error=await workspace.save_to("user://async_building.res"); var loaded:=ResourceLoader.load("user://async_building.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(saved==OK and Buildings.source(loaded.component(id)).roof_pitch==54.,"Save waits for generated building geometry before writing the native resource")
	next=Source.copy(Edit.source(session,id)); next.roof_pitch=55.; send(session,id,next); workspace.capture_state(); workspace.open_source(KiwiModelDocument.new()); await Edit.flush(session)
	check(workspace.session!=session and workspace.session.document.components.is_empty() and Buildings.source(session.document.component(id)).roof_pitch==55.,"Switching documents keeps pending generation attached to its original session")
	next=Source.copy(Edit.source(session,id)); next.roof_pitch=57.; send(session,id,next); session.action("Rename",func(): session.document.component(id).title="Changed while generating"); await Edit.flush(session)
	check(session.document.component(id).title=="Changed while generating" and Buildings.source(session.document.component(id)).roof_pitch==55.,"A newer history edit cancels an unfinished source result")
	var job:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_job.gd").new(); job.cancel(); job.start(Source.copy(Edit.source(session,id)))
	while not job.complete(): await process_frame
	check(job.collect().get("cancelled",false),"Cancelled background generation returns no partial document")
	workspace.queue_free(); await process_frame; print("ARCHITECTURE ASYNC: %d checks, %d failures"%[checks,failures]); quit(failures)
