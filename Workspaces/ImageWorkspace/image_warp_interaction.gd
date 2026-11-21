extends RefCounted
## Canvas input and overlays; compact geometry transactions use existing history.
signal settings_changed
var canvas: Control
var mode:="brush"
var brush:="push"
var diameter:=180.0
var strength:=.5
var hardness:=.25
var pressure_enabled:=true
var show_grid:=false
var show_freeze:=true
var selection_only:=false
var pin_radius:=.3
var mesh_resolution:=4
var mesh_radius:=.5
var mesh_attenuation:=2.0
var _mesh_weights:=PackedFloat32Array()
var selected_points:=PackedInt32Array()
var selected_pin:=-1
var active:=false
var _layer_id:=""
var _last:=Vector2.ZERO
var _pointer:=Vector2.ZERO
var _start:=Vector2.ZERO
var _original:=PackedVector2Array()
var _pending:=false
var _pressure:=1.0
var _freeze_erase:=false
var _changed:=false

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_warp_interaction")

func settings() -> Dictionary:
 return _native().settings(self)

func restore_settings(values: Dictionary) -> void:
 _native().restore_settings(self,values)

func layer() -> KiwiImageLayer:
 return _native().layer(self)

func local_uv(document_point: Vector2,item: KiwiImageLayer) -> Vector2:
 return _native().local_uv(self,document_point,item)

func screen(uv: Vector2,item: KiwiImageLayer) -> Vector2:
 return _native().screen(self,uv,item)

func ensure_data(item: KiwiImageLayer) -> KiwiImageWarpData:
 return _native().ensure_data(self,item)

func begin(item: KiwiImageLayer,uv: Vector2) -> void:
 _native().begin(self,item,uv)

func handle(event: InputEvent) -> bool:
 return _native().handle(self,event)

func process(delta: float) -> void:
 _native().process(self,delta)

func finish() -> void:
 _native().finish(self)

func cancel() -> void:
 _native().cancel(self)

func hit_mesh(item: KiwiImageLayer,at: Vector2) -> int:
 return _native().hit_mesh(self,item,at)

func hit_pin(item: KiwiImageLayer,at: Vector2) -> int:
 return _native().hit_pin(self,item,at)

func draw() -> void:
 _native().draw(self)

static func mesh_weights(points: PackedVector2Array,selected: PackedInt32Array,extent: Vector2,radius: float,attenuation: float) -> PackedFloat32Array:
 return _native().mesh_weights(points,selected,extent,radius,attenuation)

static func _has_inverse(target: Control) -> bool:
 return target.selection_inverse_warp.is_valid()

static func _selection_point(target: Control,world: Vector2) -> Vector2:
 return target.selection_inverse_warp.call(world)
