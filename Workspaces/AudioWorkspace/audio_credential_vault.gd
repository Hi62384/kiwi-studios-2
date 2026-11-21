extends RefCounted
## Windows Credential Manager, current Windows user. Never stored in project files.
static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_credential_vault")
static func available()->bool:return _native().available()
static func valid_id(id:String)->bool:return _native().valid_id(id)
static func request(action:String,id:String,secret:String="",job:RefCounted=null)->Dictionary:
 return _native().request(action,id,secret,job)
static func read(id:String)->String:return _native().read(id)
