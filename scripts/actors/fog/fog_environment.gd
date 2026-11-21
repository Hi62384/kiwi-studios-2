extends Node
## One coordinator per viewport. Copies only the Environment resource, retains
## its sky and every unrelated option, and restores the owner when fog ends.
var world: World3D
var source: Environment
var overlay: Environment
var source_dirty:=true
var entries: Array[WeakRef]=[]
var camera_ref: WeakRef
var camera_source: Environment
var camera_overlay: Environment
var camera_dirty:=true
var source_signature: int=0
var camera_signature: int=0
static var environment_keys: PackedStringArray=[]
var lights: Array[WeakRef]=[]
var shadow_signature: int=-1
var resize_frame: int=-1
var original_scale:=1.
var temporary_scale:=1.

func _ready() -> void:
	_native().ready(self)

func _light_added(node: Node) -> void:
	_native().light_added(self,node)

func _sync_shadow_buffers() -> void:
	_native().sync_shadow_buffers(self)

static func attach(runtime: Node) -> void:
	_native().attach(runtime)

func _process(_delta: float) -> void:
	_native().process(self,_delta)

func _sync_camera(global_fog: bool) -> void:
	_native().sync_camera(self,global_fog)

func _camera_changed() -> void: camera_dirty=true
func _restore_camera() -> void:
	_native().restore_camera(self)

static func environment_signature(environment: Environment) -> int:
	return _native().environment_signature(environment)

func _dirty() -> void: source_dirty=true
func _exit_tree() -> void:
	_native().exit_tree(self)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_environment")
