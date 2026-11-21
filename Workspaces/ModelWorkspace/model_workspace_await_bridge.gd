extends Node
## Temporary await adapter for shared file dialogs and world/architecture flush
## APIs which have not yet migrated. No model save behavior lives here.
signal completed(value: Variant)
var resolved:=false
func run(kind: String,workspace: Control,arguments: Array) -> void:
	await get_tree().process_frame
	if not is_inside_tree(): return
	var result: Variant
	match kind:
		"world_flush": result=await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(arguments[0])
		"world_edit": result=await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").request(arguments[0],str(arguments[1]),arguments[2],str(arguments[3]))
		"resource_save": result=await ActorProjectResourceSaveDialog.pick(workspace,str(arguments[0]),str(arguments[1]),str(arguments[2]),false,PackedStringArray(arguments[3]),arguments[4])
		"flatten_image": result=await arguments[0].flattened()
		"thumbnail": result=await FileOperations.get_file_thumbnail(str(arguments[0]))
		"flush": result=await preload("res://Workspaces/ModelWorkspace/natural_edit.gd").flush(workspace)
		"pick_file": result=await ActorProjectFilePicker.pick(workspace,arguments[0],str(arguments[1]),bool(arguments[2]) if arguments.size()>2 else false)
		"save_as": result=await ActorProjectResourceSaveDialog.pick(workspace,"Save editable 3D model",str(arguments[0]),"tres",false,PackedStringArray(["tres","res"]),arguments[1])
	if not is_inside_tree() or resolved: return
	resolved=true; completed.emit(result); queue_free()
func _exit_tree() -> void:
	if not resolved: resolved=true; completed.emit(null)
static func refresh_filesystem() -> void:
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()

func world_edit_now(session: KiwiEnvironmentSession,id: String,desired: Resource,label: String) -> void:
	var result: Variant=await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").request(session,id,desired,label)
	if not is_inside_tree() or resolved: return
	resolved=true; completed.emit(result); queue_free()
func world_flush_now(session: KiwiModelSession) -> void:
	var result: Variant=await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(session)
	if not is_inside_tree() or resolved: return
	resolved=true; completed.emit(result); queue_free()
