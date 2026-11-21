extends RefCounted
static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_healing")
static func mean(image:Image,area:Rect2i,excluded:Rect2i=Rect2i())->Color:return _native().mean(image,area,excluded)
static func adapt(sample:Color,source_mean:Color,destination_mean:Color,preserve:float)->Color:return _native().adapt(sample,source_mean,destination_mean,preserve)
static func spot_patch(image:Image,area:Rect2i,settings:Dictionary,excluded:Rect2i)->Image:return _native().spot_patch(image,area,settings,excluded,settings.get("cancelled",Callable()).is_valid())
static func _cancelled(callback:Callable)->bool:return bool(callback.call())
