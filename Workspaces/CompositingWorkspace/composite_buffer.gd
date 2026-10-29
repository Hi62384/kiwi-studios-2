class_name KiwiCompositeBuffer
extends RefCounted
## Pixels plus the interpretation required to process them correctly.
var image: Image
var pixel_aspect_ratio:=1.0
var channel_layout:=&"RGBA"
var precision:=&"float32"
var color_space:=&"linear_srgb"
var alpha_association:=&"straight"
var coordinate_domain:=&"canvas"
var frame_time:=0.0
var source_identity:=""
var depth_convention:=&""
var depth_units:=&""
var camera_reference:=""
var validity: Image

func is_valid() -> bool:
	return image!=null and not image.is_empty() and image.get_width()>0 and image.get_height()>0 and is_finite(pixel_aspect_ratio) and pixel_aspect_ratio>0.

func duplicate_buffer() -> KiwiCompositeBuffer:
	var result:=KiwiCompositeBuffer.new(); result.image=image.duplicate() if image!=null else null; result.pixel_aspect_ratio=pixel_aspect_ratio; result.channel_layout=channel_layout; result.precision=precision; result.color_space=color_space; result.alpha_association=alpha_association; result.coordinate_domain=coordinate_domain; result.frame_time=frame_time; result.source_identity=source_identity; result.depth_convention=depth_convention; result.depth_units=depth_units; result.camera_reference=camera_reference; result.validity=validity.duplicate() if validity!=null else null; return result
