extends SceneTree
const Workspace=preload("res://Workspaces/CompositingWorkspace/compositing_workspace.gd")
const Document=preload("res://Workspaces/CompositingWorkspace/compositing_document.gd")
const Layer=preload("res://Workspaces/CompositingWorkspace/composite_layer.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var document=Document.new(); document.title="Workspace test"; document.canvas_size=Vector2i(8,4); document.layers.clear(); var background=document.add_layer(Layer.Kind.SOLID,"Background"); background.color=Color(.2,.1,.05,1.)
	var workspace=Workspace.new(); root.add_child(workspace); await process_frame; workspace.open_source(document); await process_frame
	check(workspace.image_view.texture!=null and workspace.dirty,"New compositions open in the dedicated workspace and render an interactive preview")
	workspace._add_layer(Layer.Kind.SOLID); var selected=workspace.document.layer(workspace.selected_id); selected.color=Color.BLUE; workspace._render(); check(workspace.document.layers.size()==2 and workspace.image_view.texture!=null,"Workspace adds and previews editable layers")
	workspace.undo(); check(workspace.document.layers.size()==1,"Workspace layer edits participate in undo")
	workspace.redo(); check(workspace.document.layers.size()==2,"Workspace layer edits participate in redo")
	workspace._new_graph(); workspace._add_graph_node("Solid Color"); var graph=workspace.document.graphs[0]
	check(graph.nodes.size()==2 and graph.compile_errors().size()>=1,"Workspace preserves graph node data and flags disconnected required inputs")
	workspace._set_mode(1); workspace._filter_graph_nodes("luma"); var luma_visible:=false; var source_visible:=false
	for button in workspace._graph_node_controls:
		if button.text=="Luma Key": luma_visible=button.visible
		if button.text=="Image Source": source_visible=button.visible
	check(workspace.graph_search.visible and luma_visible and not source_visible,"Graph node search filters the node library by name")
	var path: String="user://compositing_workspace_"+ActorData.new_id()+".tres"; workspace._save_path(path); var loaded=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiCompositingDocument
	check(loaded!=null and loaded.validate().is_empty() and loaded.layers.size()==2 and loaded.graphs.size()==1,"Workspace saves complete editable layer and node graph state")
	if not ActorVideo.executable("ffmpeg").is_empty():
		workspace.document.duration=.25; workspace.document.frame_rate=8.; var export_path: String="user://compositing_workspace_export_"+ActorData.new_id()+".mp4"; var exported: bool=await workspace.export_video(export_path)
		check(exported and FileAccess.get_file_as_bytes(export_path).size()>0,"Workspace renders a silent MP4 from evaluated composition frames"); DirAccess.remove_absolute(export_path)
	workspace._set_mode(0); workspace._add_layer(Layer.Kind.ADJUSTMENT); var adjustment=workspace.document.layer(workspace.selected_id); workspace._refresh_inspector(); var curve_editor: Control
	for child in workspace.inspector.get_children():
		if child.has_signal("points_changed"): curve_editor=child; break
	if curve_editor!=null:
		curve_editor.emit_signal("edit_started"); curve_editor.emit_signal("points_changed",[Vector2(0.,0.),Vector2(.5,.8),Vector2(1.,1.)]); curve_editor.emit_signal("edit_finished")
	check(curve_editor!=null and adjustment.settings.get("curves",{}).get("master",[]).size()==3,"Adjustment curves can be edited from the channel curve control")
	workspace.undo(); check(not workspace.document.layer(adjustment.id).settings.get("curves",{}).has("master"),"Curve editing is one undoable workspace change")
	var group=workspace.document.add_layer(Layer.Kind.GROUP,"Hierarchy test"); var child=workspace.document.add_layer(Layer.Kind.SOLID,"Animated child"); child.parent_id=group.id; workspace.document.set_layer_key(child.id,"opacity",0.,.3); workspace.selected_id=group.id
	var original_count: int=workspace.document.layers.size(); workspace._duplicate_layer(); var copied_group=workspace.document.layer(workspace.selected_id); var copied_child: KiwiCompositeLayer
	for item in workspace.document.layers:
		if item.parent_id==copied_group.id: copied_child=item
	check(workspace.document.layers.size()==original_count+2 and copied_child!=null and workspace.document.has_layer_track(copied_child.id,"opacity"),"Group duplication preserves child hierarchy and animation ownership")
	workspace.undo(); check(workspace.document.layers.size()==original_count,"Duplicating a hierarchy is undone as one operation")
	workspace.selected_id=group.id; workspace._copy_layer(); var destination=Workspace.new(); root.add_child(destination); await process_frame; var destination_document=Document.new(); destination_document.canvas_size=Vector2i(8,4); destination.open_source(destination_document); var destination_count: int=destination.document.layers.size(); destination._paste_layer(); var pasted_group=destination.document.layer(destination.selected_id); var pasted_child: KiwiCompositeLayer
	for item in destination.document.layers:
		if item.parent_id==pasted_group.id: pasted_child=item
	check(destination.document.layers.size()==destination_count+2 and pasted_child!=null and destination.document.has_layer_track(pasted_child.id,"opacity"),"Copy and paste preserve animated hierarchies across composition documents")
	destination.queue_free()
	var sequence_directory: String="user://composite_sequence_"+ActorData.new_id(); var sequence_ok: bool=await workspace.export_sequence(sequence_directory,"png"); var frame_file:=sequence_directory.path_join(workspace.document.title.validate_filename()+"_000000.png"); var sequence_image:=Image.load_from_file(ProjectSettings.globalize_path(frame_file))
	check(sequence_ok and sequence_image!=null and sequence_image.get_size()==workspace.document.canvas_size,"PNG sequence export writes frames at composition resolution")
	workspace.document.solo_layer_id=workspace.document.layers[0].id; workspace.document.layers[0].color=Color(2.,.5,.25,.4); workspace.evaluator.clear_cache(); var exr_ok: bool=await workspace.export_sequence(sequence_directory,"exr"); var exr_file:=sequence_directory.path_join(workspace.document.title.validate_filename()+"_000000.exr"); var exr_image:=Image.load_from_file(ProjectSettings.globalize_path(exr_file))
	check(exr_ok and exr_image!=null and exr_image.get_pixel(0,0).r>1. and absf(exr_image.get_pixel(0,0).a-.4)<.01,"EXR sequences preserve HDR intensity and fractional alpha")
	for file in DirAccess.get_files_at(sequence_directory): DirAccess.remove_absolute(sequence_directory.path_join(file))
	DirAccess.remove_absolute(sequence_directory)
	DirAccess.remove_absolute(path); workspace.queue_free(); print("COMPOSITING WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
