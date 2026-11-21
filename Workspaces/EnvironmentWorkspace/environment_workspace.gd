class_name KiwiEnvironmentWorkspace
extends Control
signal document_changed
signal environment_saved(path: String,saved_session: KiwiEnvironmentSession)
signal use_in_scene(path: String)
var session:=KiwiEnvironmentSession.new()
var canvas:=KiwiEnvironmentViewport.new()
var path:=""
var title:=Label.new()
var status:=Label.new()
var hierarchy: Tree=preload("res://Workspaces/ModelWorkspace/ModelHierarchy.cs").new()
var properties:=VBoxContainer.new()
var search:=LineEdit.new()
var _split:=HSplitContainer.new()
var _right_split:=HSplitContainer.new()
var _left:=VBoxContainer.new()
var _right:=ScrollContainer.new()
var _context:=HBoxContainer.new()
var _building:=false
var _refresh_pending:=false
var _last_selection:=""
var _recent_assets: Array[String]=[]
var _asset_name:=Button.new()
var _transform_inputs: Dictionary={}
var _settings_mode:=false
const Climate=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentClimate.cs")
var _climate_mode:=false
var _collapsed: Dictionary={}
var _property_scrolls: Dictionary={}
var _generation_jobs: Array[Dictionary]=[]
var _generation_cancel:=Button.new()
var _terrain_bake: RefCounted
var library:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentLibrary.cs").new()
var _expanded_landforms: Dictionary={}
var _advanced_generation:=false
var _failed_volumes: Dictionary={}

func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_workspace")
func _ready() -> void:
	_native().call("ready",self)

func _button(parent: Node,text: String,action: Callable,tooltip: String="") -> Button:
	var button:=Button.new(); button.text=text; button.tooltip_text=tooltip; parent.add_child(button); button.pressed.connect(action); return button
func _clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()
func _changed() -> void:
	_native().call("changed",self)
func _process(_delta: float) -> void:
	_native().call("process",self)
func _refresh_tree() -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_hierarchy").call("refresh",self)
func _store_collapsed(row: TreeItem) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_hierarchy").call("store_collapsed",self,row)
func _tree_selected(item: TreeItem,column: int,selected: bool) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_hierarchy").call("selected",self,item,column,selected)
func _tree_edited() -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_hierarchy").call("edited",self)

func _refresh_context() -> void:
	_native().call("refresh_context",self)
func _choose_stamp() -> void:
	_native().call("choose_file",self,"stamp","",0)
func _value(parent: Node,label: String,value: float,low: float,high: float,step: float,write: Callable) -> DragNumber:
	var row:=HBoxContainer.new(); parent.add_child(row); var title:=Label.new(); title.text=label; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title); var input:=DragNumber.new(); input.min_value=low; input.max_value=high; input.step=step; input.custom_minimum_size.x=85; input.set_value_no_signal(value); row.add_child(input); input.value_changed.connect(write); input.drag_committed.connect(write); return input
func _heading(text: String) -> void:
	var label:=Label.new(); label.text=text; label.add_theme_color_override("font_color",Color("7edbc4")); properties.add_child(label)
func _transform_value(item: KiwiModelComponent,kind: String,axis: int) -> float:
	return _native().call("transform_value",item,kind,axis)
func _edit_transform(item: KiwiModelComponent,kind: String,axis: int,value: float) -> void:
	_native().call("edit_transform",self,item,kind,axis,value)
func _refresh_properties() -> void:
	_native().call("refresh_properties",self)
func _restore_property_scroll(id: String) -> void:
	_native().call("restore_property_scroll",self,id)

func _scatter_instances(item: KiwiModelComponent,scatter: KiwiEnvironmentScatter) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_scatter_ui").call("instances",self,item,scatter)

func _invoke_source_edit(state: Dictionary,value: Variant) -> void:
	state.callback.call(value)
func _edit_generation(id: String,edit: Callable) -> void:
	_native().call("edit_generation",self,id,{"callback":edit})
func _edit_erosion(id: String,edit: Callable) -> void:
	_native().call("edit_erosion",self,id,{"callback":edit})
func _set_scatter_biome(scatter: KiwiEnvironmentScatter,id: String,enabled: bool) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_scatter_ui").call("set_biome",self,scatter,id,enabled)
func _edit_biomes(id: String,edit: Callable) -> void:
	_native().call("edit_biomes",self,id,{"callback":edit})
func _biome_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_native().call("biome_properties",self,item,terrain)
func _choose_biome_material(id: String,index: int) -> void:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentWorkspaceFileJob.cs").new()
	add_child(job); job.start(self,"biome",id,index)
func _edit_water(id: String,edit: Callable) -> void:
	_native().call("edit_water",self,id,{"callback":edit})
func _water_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_native().call("water_properties",self,item,terrain)
func _edit_caves(id: String,edit: Callable) -> void:
	_native().call("edit_caves",self,id,{"callback":edit})
func _replace_cave(id: String,cave: KiwiTerrainCave) -> void:
	_native().call("replace_cave",self,id,cave)
func _add_cave(kind: int=0) -> void:
	_native().call("add_cave",self,kind)
func _cave_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_native().call("cave_properties",self,item,terrain)
func _erosion_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_native().call("erosion_properties",self,item,terrain)
func _generation_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_native().call("generation_properties",self,item,terrain)

func choose_asset() -> String:
	var job = _native().call("choose_file",self,"asset","",0)
	if not job.finished: await job.completed
	return job.result
func _library_asset(asset: String) -> void:
	_native().call("library_asset",self,asset)
func _add_palette_asset(id: String) -> void:
	_native().call("choose_file",self,"palette",id,0)
func _save_component() -> void:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentWorkspaceComponentJob.cs").new()
	add_child(job); job.start(self,"component","")
func _choose_material(id: String,paint: bool=false) -> void:
	_native().call("choose_file",self,"paint" if paint else "ground",id,0)
func _bake_terrain(id: String) -> void:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentWorkspaceComponentJob.cs").new()
	add_child(job); job.start(self,"bake",id)
func _environment_properties() -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_lighting_ui").call("properties",self)

func _climate_properties() -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_climate_ui").call("properties",self)

func _local_weather_properties(source: Resource) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","environment_climate_ui").call("local_properties",self,source)

func _choose_world() -> void:
	_native().call("choose_file",self,"world","",0)
func _add_scatter() -> void:
	_native().call("add_scatter",self)
func _command(command: String) -> void:
	_native().call("command",self,command)
func _to_scene() -> void:
	await _save_mode("to_scene")
func _place_tool() -> void:
	_native().call("place_tool",self)
func _open_model(source: String) -> void:
	_native().call("open_model",self,source)
func _open_library_source(source: String) -> void:
	_native().call("open_library_source",self,source)
func open_source(value: Variant,state: Dictionary={}) -> bool:
	return _native().call("open_source",self,value,state)
func capture_state() -> Dictionary:
	return _native().call("capture_state",self)
func _editor_state() -> Dictionary:
	return _native().call("editor_state",self)
func open_dialog() -> void:
	_native().call("choose_file",self,"open","",0)
func save() -> Error:
	return await _save_mode("save")
func save_as() -> Error:
	return await _save_mode("save_as")
func _save_mode(mode: String) -> Error:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentWorkspaceSaveJob.cs").new()
	add_child(job); job.start_mode(self,mode)
	if not job.finished: await job.completed
	return job.result
func save_to(destination: String) -> Error:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/EnvironmentWorkspaceSaveJob.cs").new()
	add_child(job); job.start(self,destination)
	if not job.finished: await job.completed
	return job.result
func _unhandled_key_input(event: InputEvent) -> void:
	_native().call("unhandled_key_input",self,event)
func _regenerate_terrain(id: String,settings: Dictionary,reset_edits: bool=false,derived_only: bool=false) -> void:
	_native().call("regenerate_terrain",self,id,settings,reset_edits,derived_only)
func _cancel_generation(suspend_worlds: bool=true) -> void:
	_native().call("cancel_generation",self,suspend_worlds)
func _poll_generation() -> void:
	_native().call("poll_generation",self)
func _exit_tree() -> void:
	_native().call("exit_tree",self)
