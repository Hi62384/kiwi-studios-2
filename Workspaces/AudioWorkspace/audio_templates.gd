class_name KiwiAudioTemplates
extends RefCounted
static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_templates")
static func names()->PackedStringArray:return _native().names()
static func create(label:String)->KiwiAudioDocument:return _native().create(label)
static func chain_names()->PackedStringArray:return _native().chain_names()
static func chain(name:String)->Array:return _native().chain(name)
static func _fx(type:String,values:Dictionary)->Dictionary:return _native().effect(type,values)
static func export_presets()->Dictionary:return _native().export_presets()
