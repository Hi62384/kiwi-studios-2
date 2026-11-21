extends RefCounted
## Optional stamp mapping for the normal Brush pipeline. Coverage remains native
## brush ink; only local texture coordinates differ, so live edits remain lossless.
## Map allocation is capped at 2048 pixels per axis and cropped on commit.
var value: KiwiTextureMaterial
var coordinates: Image
var texture: ImageTexture
var coordinate_size:=Vector2i.ZERO
var source_size:=Vector2i.ZERO
var bounds:=Rect2i()
var distance:=0.0
var started:=false
var direction:=0.0
var tail_backup: Image
var tail_area:=Rect2i()

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_material_stamps")

func begin(canvas: KiwiImageCanvas,material: KiwiTextureMaterial) -> void:
 _native().begin(self,canvas,material)

func interval(canvas: KiwiImageCanvas) -> float:
 return _native().interval(self,canvas)

func radius_factor() -> float:
 return _native().radius_factor(self)

func paint_line(canvas: KiwiImageCanvas,from: Vector2,to: Vector2,upload: bool) -> void:
 _native().paint_line(self,canvas,from,to,upload)

func dab(canvas: KiwiImageCanvas,point: Vector2) -> void:
 _native().dab(self,canvas,point)

func map_area(source: Rect2i) -> Rect2i:
 return _native().map_area(self,source)

func restore_tail() -> void:
 _native().restore_tail(self)

func capture_tail(area: Rect2i) -> void:
 _native().capture_tail(self,area)

func upload(region: KiwiLivePaintRegion) -> void:
 _native().upload(self,region)

func commit(region: KiwiLivePaintRegion) -> void:
 _native().commit(self,region)
