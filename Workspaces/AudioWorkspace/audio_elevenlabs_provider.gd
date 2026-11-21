extends KiwiAudioProvider
## Optional, opt-in official ElevenLabs speech endpoint. No request on construction.
## https://elevenlabs.io/docs/api-reference/text-to-speech/convert
var transport:=Callable() # Test seam; production always uses verified TLS below.
func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_elevenlabs")
func descriptor()->Dictionary:return _native().descriptor()
func generate(request:Dictionary,credential:String,job:RefCounted=null)->Dictionary:
 return _native().generate(self,request,credential,job)
func _request(voice:String,body:PackedByteArray,key:String,job:RefCounted)->Dictionary:
 return _native().request_audio(voice,body,key,job)
func _has_transport()->bool:return transport.is_valid()
func _dispatch_transport(voice:String,body:PackedByteArray,key:String,job:RefCounted)->Dictionary:
 return transport.call(voice,body,key,job)
