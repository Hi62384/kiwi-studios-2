class_name KiwiRigEditor
extends RefCounted
const Native=preload("res://Workspaces/ModelWorkspace/rig/RigEditor.cs")
var _native: RefCounted=Native.new()
# Compatibility interface for typed callers and GDScript default arguments.
var session: KiwiModelSession:
	get: return _native.session
	set(value): _native.session=value
var rig_id: String="":
	get: return _native.rig_id
	set(value): _native.rig_id=value
var selected_bone: int:
	get: return _native.selected_bone
	set(value): _native.selected_bone=value
var enabled: bool=false:
	get: return _native.enabled
	set(value): _native.enabled=value
var mode: String="Edit":
	get: return _native.mode
	set(value): _native.mode=value
var symmetry: bool=false:
	get: return _native.symmetry
	set(value): _native.symmetry=value
var symmetry_axis: int=0:
	get: return _native.symmetry_axis
	set(value): _native.symmetry_axis=value
var symmetry_offset: float=0.:
	get: return _native.symmetry_offset
	set(value): _native.symmetry_offset=value
var show_bones: bool=true:
	get: return _native.show_bones
	set(value): _native.show_bones=value
var only_chain: bool=false:
	get: return _native.only_chain
	set(value): _native.only_chain=value
var connected: bool=true:
	get: return _native.connected
	set(value): _native.connected=value
var busy: bool=false:
	get: return _native.busy
	set(value): _native.busy=value
var message: String="":
	get: return _native.message
	set(value): _native.message=value
func _init(owner: KiwiModelSession=null) -> void: session=owner
func rig() -> KiwiModelComponent: return _native.rig()
func meshes() -> Array[KiwiModelComponent]:
	var result: Array[KiwiModelComponent]=[]; result.assign(_native.meshes()); return result
func bounds() -> AABB: return _native.bounds()
func create(kind: String="Flexible chain", count: int=6) -> KiwiModelComponent: return _native.create(kind,count)
func empty_rig() -> KiwiModelComponent: return _native.empty_rig()
func bind(method: String="Smooth", influences: int=4) -> String: return _native.bind(method,influences)
func install_bindings(id: String, bindings: Dictionary) -> String: return _native.install_bindings(id,bindings)
func can_edit_rest() -> bool: return _native.can_edit_rest()
func add(head: Vector3, tail: Vector3, parent_index: int=-1) -> void: _native.add(head,tail,parent_index)
func move_joint(index: int, end: bool, point: Vector3) -> void: _native.move_joint(index,end,point)
func reset_pose(all: bool=false) -> void: _native.reset_pose(all)
func pose(channel: String, value: Vector3) -> void: _native.pose(channel,value)
func rename(title: String) -> void: _native.rename(title)
func parent(parent_index: int, connect: bool=false) -> void: _native.parent(parent_index,connect)
func delete_bone() -> void: _native.delete_bone()
func insert_joint() -> void: _native.insert_joint()
func duplicate_chain(mirror: bool=false) -> void: _native.duplicate_chain(mirror)
func _mirror(armature: KiwiModelComponent, chosen: PackedInt32Array, reflect: bool=true) -> void: _native.mirror_chain(armature,chosen,reflect)
func preset() -> Resource: return _native.preset()
func load_preset(value: Resource, fit: bool=true) -> bool: return _native.load_preset(value,fit)
func adopt_imported() -> String: return _native.adopt_imported()
func cleanup(kind: String="Fix Weights") -> String: return _native.cleanup(kind)
func detach() -> void: _native.detach()
static var _bindings: RefCounted=preload("res://Workspaces/ModelWorkspace/rig/RigBindingWeights.cs").new()
static var _importer: RefCounted
static func source(item: KiwiModelComponent) -> Mesh:
	if _importer==null: _importer=preload("res://Workspaces/ModelWorkspace/rig/RigBindingImport.cs").new()
	return _importer.source(item)
static func refresh_bindings(document: KiwiModelDocument, armature: KiwiModelComponent, remap: bool=false, fallback: Dictionary={}) -> void: _bindings.refresh_bindings(document,armature,remap,fallback)
static func apply_weight_patch(target: Variant, patch: Dictionary) -> void: _bindings.apply_weight_patch(target,patch)
