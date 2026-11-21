extends RefCounted
## Native hierarchy insertion and anchor alignment; authored API defaults retained.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_modules")
static func insert(session: KiwiModelSession,parent_id: String,path: String,pose: Transform3D=Transform3D.IDENTITY,own_path: String="") -> Dictionary:
	return _native().call("insert",session,parent_id,path,pose,own_path)
static func anchors(item: KiwiModelComponent) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	result.assign(_native().call("anchors",item))
	return result
static func snap(session: KiwiModelSession,id: String,anchor: Transform3D,target_id: String,target_anchor: Transform3D,mate: bool=true) -> String:
	return _native().call("snap",session,id,anchor,target_id,target_anchor,mate)
