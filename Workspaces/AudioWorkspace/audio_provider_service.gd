class_name KiwiAudioProviderService
extends RefCounted
## A provider cannot receive a credential or send audio without explicit request consent.
## Credential callbacks must use an OS vault; credentials are never serialized here.
var providers:Dictionary={}
var credential_reader:=Callable()
func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_provider_service")
func register(provider:KiwiAudioProvider)->Error:return _native().register(self,provider)
func catalog()->Array:return _native().catalog(self)
func run(provider_id:String,request:Dictionary,consent:Dictionary,job:RefCounted=null)->Dictionary:
 return _native().run(self,provider_id,request,consent,job)
func _has_credential_reader()->bool:return credential_reader.is_valid()
func _read_credential(id:String)->String:return str(credential_reader.call(id))
