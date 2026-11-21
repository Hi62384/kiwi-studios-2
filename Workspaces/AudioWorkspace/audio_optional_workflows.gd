extends Node
## UI/main-thread ownership for optional tools; background work never mutates UI.
const Transcription=preload("res://Workspaces/AudioWorkspace/AudioTranscription.cs")
const Vault=preload("res://Workspaces/AudioWorkspace/audio_credential_vault.gd")
const Provider=preload("res://Workspaces/AudioWorkspace/audio_elevenlabs_provider.gd")
const CONFIG="user://audio_workspace/optional_tools.cfg"
var jobs:=KiwiAudioJobs.new()
var settings:Dictionary={"whisper":"","model":"","voice_id":""}
var contexts:Dictionary={}
var service:=KiwiAudioProviderService.new()
func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_optional_workflows")
func _initialize_provider()->void:
 service.register(Provider.new());service.credential_reader=Vault.read
func _remember(kind:String,context:Dictionary)->String:return _native().remember(self,kind,context)
func _ready()->void:_native().ready(self)
func _context()->Dictionary:return _native().context(self)
func _current(context:Dictionary)->bool:return _native().current(self,context)
func _field(parent:Node,label:String,text:String,secret:bool=false)->LineEdit:return _native().field(self,parent,label,text,secret)
func _path(parent:Node,label:String,key:String,filters:PackedStringArray)->LineEdit:return _native().path(self,parent,label,key,filters)
func configure()->void:_native().configure(self)
func transcribe()->void:_native().transcribe(self)
func review_saved_transcript()->void:_native().review_saved_transcript(self)
func speech()->void:_native().speech(self)
func _completed(kind:String,_generation:int,result:Variant)->void:_native().completed(self,kind,result)
func _review(context:Dictionary,result:Dictionary)->void:_native().review(self,context,result)
func cancel()->void:_native().cancel(self)
