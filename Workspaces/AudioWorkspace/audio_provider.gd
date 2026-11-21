class_name KiwiAudioProvider
extends RefCounted
## Optional provider contract. Subclasses supply an independently reviewed adapter.
## No provider, model, subscription, credential or remote operation is enabled by default.
const TASKS := ["sound_effect","music","speech","transform","extend","variation","restore"]
func descriptor()->Dictionary:
 return Engine.get_singleton("KiwiNativeServices").service("audio_provider_contract").descriptor()
func estimate(_request:Dictionary)->Dictionary:
 return Engine.get_singleton("KiwiNativeServices").service("audio_provider_contract").estimate()
func generate(_request:Dictionary,_credential:String,_job:RefCounted=null)->Dictionary:
 return Engine.get_singleton("KiwiNativeServices").service("audio_provider_contract").generate()
func cancel(_request_id:String)->void:
 pass
