class_name KiwiAudioProvider
extends RefCounted
## Optional provider contract. Subclasses supply an independently reviewed adapter.
## No provider, model, subscription, credential or remote operation is enabled by default.
const TASKS := ["sound_effect","music","speech","transform","extend","variation","restore"]
func descriptor()->Dictionary:
 return {"id":"","label":"Unconfigured provider","tasks":[],"models":[],"supports_cancel":false,"credential_required":true}
func estimate(_request:Dictionary)->Dictionary:
 return {"known":false,"amount":0.0,"currency":"","unit":"request"}
func generate(_request:Dictionary,_credential:String,_job:RefCounted=null)->Dictionary:
 return {"success":false,"error":"This provider has no generation adapter."}
func cancel(_request_id:String)->void:
 pass
