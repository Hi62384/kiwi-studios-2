class_name KiwiRigUI
extends RefCounted
var _toolbar: RefCounted=preload("res://Workspaces/ModelWorkspace/rig/RigUiToolbar.cs").new()
var _inspector: RefCounted=preload("res://Workspaces/ModelWorkspace/rig/RigUiInspector.cs").new()
var workspace: KiwiModelWorkspace
var _binder: Node=preload("res://Workspaces/ModelWorkspace/rig/RigBindingWorker.cs").new()
var job: RefCounted:
	get: return _binder.get("job") if is_instance_valid(_binder) else null
var worker: Thread:
	get: return _binder.get("worker") if is_instance_valid(_binder) else null
var method := "Smooth"
var chain_count := 6
var test_axis := 2
func _init(owner: KiwiModelWorkspace) -> void:
	workspace=owner
	_binder.name="RigBindingWorker"
	workspace.add_child(_binder)
	_binder.call("configure",workspace)
	_binder.connect("updated",refresh)
func editor() -> KiwiRigEditor: return workspace.canvas.rig_tool.editor
func refresh() -> void: _toolbar.call("refresh",workspace)
func set_mode(value: String) -> void:
	_toolbar.call("set_mode",workspace,value)
func quick_rig() -> void:
	_toolbar.call("quick_rig",workspace,self)
func templates() -> void:
	_toolbar.call("templates",workspace,self)
func build_context(parent: HBoxContainer) -> void:
	_toolbar.call("build_context",workspace,self,parent)
func build_properties(parent: VBoxContainer) -> void:
	_inspector.call("build_properties",workspace,self,parent)
func weight_controls(parent: VBoxContainer) -> void:
	_inspector.call("weight_controls",workspace,self,parent)
func more_menu() -> void:
	_toolbar.call("more_menu",workspace,self)
func bind_async(style: String) -> void:
	if _binder.call("start_binding",editor().get("_native"),style):
		await _binder.finished

func cancel_job() -> void:
	if is_instance_valid(_binder): _binder.call("cancel_job")
func save_preset() -> void:
	if editor().rig()==null: return
	var result := await ActorProjectResourceSaveDialog.pick(workspace,"Save reusable armature",editor().rig().title,"tres",false,PackedStringArray(),editor().preset())
	if not result.get("cancelled",true):
		var error := ResourceSaver.save(editor().preset(),str(result.path)); editor().message="Rig preset saved." if error==OK else "Save failed (%d)."%error
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
	refresh()
func load_preset() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["KiwiRigPreset"]}
	var path := await ActorProjectFilePicker.pick(workspace,property,"Load and fit a reusable armature")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var resource: Resource=ResourceLoader.load(path)
	if not editor().load_preset(resource): editor().message="Invalid rig preset."
	refresh()
