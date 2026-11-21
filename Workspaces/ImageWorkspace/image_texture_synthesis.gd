extends RefCounted
static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_texture_synthesis")
static func difference(a:Color,b:Color)->float:return _native().difference(a,b)
static func inside_sample(point:Vector2,area:Rect2i,settings:Dictionary)->bool:return _native().inside_sample(point,area,settings)
static func valid_patch(candidate:Vector2i,extent:Vector2i,area:Rect2i,settings:Dictionary)->bool:return _native().valid_patch(candidate,extent,area,settings)
static func synthesize(destination:Image,source:Image,source_area:Rect2i,mask:Image,settings:Dictionary,origin:Vector2i=Vector2i.ZERO,excluded:Rect2i=Rect2i())->Image:return _native().synthesize(destination,source,source_area,mask,settings,origin,excluded,settings.get("cancelled",Callable()).is_valid())
static func seam(destination:Image,patch:Image,origin:Vector2i,width:int,vertical:bool)->PackedInt32Array:return _native().seam(destination,patch,origin,width,vertical)
static func _cancelled(callback:Callable)->bool:return bool(callback.call())
