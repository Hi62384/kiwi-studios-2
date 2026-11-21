class_name KiwiImageWarpBrush
extends RefCounted
static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_warp")
static func stroke(data:KiwiImageWarpData,extent:Vector2,from:Vector2,to:Vector2,diameter:float,strength:float,hardness:float,kind:String,elapsed:float=1.0)->bool:return _native().stroke(data,extent,from,to,diameter,strength,hardness,kind,elapsed)
static func _dab(data:KiwiImageWarpData,extent:Vector2,center:Vector2,movement:Vector2,radius:float,strength:float,hardness:float,kind:String,elapsed:float)->void:_native().dab(data,extent,center,movement,radius,strength,hardness,kind,elapsed)
