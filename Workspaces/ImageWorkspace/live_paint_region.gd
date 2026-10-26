class_name KiwiLivePaintRegion
extends Resource
## One ordered paint segment within a layer. Coverage and raster textures are
## immutable between gestures so document history can share their storage safely.

@export var id: String = ""
@export var template_id: String = ""
@export var coverage: Texture2D
## Optional floating-point per-pixel coordinates for stamp/scatter strokes.
## Keep this as a native ImageTexture: PNG packing would destroy signed values.
@export var coordinates: Texture2D
@export var coordinate_rect := Rect2(0, 0, 1, 1)
@export var raster: Texture2D
@export var mapping := Transform2D.IDENTITY
@export var opacity: float = 1.0


func copy_region() -> KiwiLivePaintRegion:
	var result := KiwiLivePaintRegion.new()
	result.id = id
	result.template_id = template_id
	result.coverage = coverage
	result.coordinates = coordinates
	result.coordinate_rect = coordinate_rect
	result.raster = raster
	result.mapping = mapping
	result.opacity = opacity
	return result


func is_live() -> bool:
	return not template_id.is_empty()
