extends Window
## True voxel edits through axis-aligned depth slices. Slice interpolation is
## shown by the same trilinear volume texture used by the renderer.
var host: ActorInspector
var actor: ActorData
var field: ActorObjectData
var definition: ActorObjectDefinition
var view: Control
var axis:=2
var depth:=.5
var radius:=3.
var strength:=.5
var falloff:=1.
var paint_mode:=0
var grid_size:=32
var painting:=false
var before: Dictionary={}
var last:=Vector2.INF
var cursor:=Vector2(-100,-100)
var image: Image
var texture: ImageTexture

func setup(inspector: ActorInspector,owner_actor: ActorData,object: ActorObjectData,object_definition: ActorObjectDefinition) -> void:
	_native().setup(self,inspector,owner_actor,object,object_definition)

func refresh() -> void:
	_native().refresh(self)

func point(x: int,y: int) -> Vector3i:
	return _native().point(self,x,y)

func _draw() -> void:
	_native().draw(self)

func _input_slice(event: InputEvent) -> void:
	_native().input_slice(self,event)

func _unhandled_key_input(event: InputEvent) -> void:
	_native().unhandled_key_input(self,event)

func dab(position: Vector2) -> void:
	_native().dab(self,position)

func commit() -> void:
	_native().commit(self)

func _close() -> void:
	_native().close(self)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_painter")
