class_name KiwiAudioProviderService
extends RefCounted
## A provider cannot receive a credential or send audio without explicit request consent.
## Credential callbacks must use an OS vault; credentials are never serialized here.
var providers:Dictionary={}
var credential_reader:=Callable()
func register(provider:KiwiAudioProvider)->Error:
 var info:=provider.descriptor();var id:=str(info.get("id",""))
 if id.is_empty() or providers.has(id):return ERR_INVALID_PARAMETER
 providers[id]=provider;return OK
func catalog()->Array:
 var output:Array=[]
 for provider in providers.values():output.append(provider.descriptor().duplicate(true))
 return output
func run(provider_id:String,request:Dictionary,consent:Dictionary,job:RefCounted=null)->Dictionary:
 if not providers.has(provider_id):return {"success":false,"error":"No compatible provider is configured."}
 var provider:KiwiAudioProvider=providers[provider_id];var info:=provider.descriptor()
 var task:=str(request.get("task","sound_effect"))
 if not task in info.get("tasks",[]):return {"success":false,"error":"The provider does not support this task."}
 if not bool(consent.get("send_request",false)):return {"success":false,"error":"Confirm sending this prompt and any selected audio to the named provider first."}
 if task=="speech" and not bool(consent.get("voice_authorized",false)):return {"success":false,"error":"Confirm that you are authorized to use the requested voice."}
 var estimate:=provider.estimate(request)
 if not bool(estimate.get("known",false)) and not bool(consent.get("unknown_cost",false)):return {"success":false,"error":"Provider cost is unknown. Explicit approval is required."}
 if bool(estimate.get("known",false)) and (str(consent.get("currency",""))!=str(estimate.get("currency","")) or float(consent.get("maximum_cost",0))<float(estimate.get("amount",0))):return {"success":false,"error":"The request exceeds the approved provider cost."}
 if job!=null and job.is_cancelled():return {"success":false,"error":"Cancelled before transmission."}
 var credential:=""
 if bool(info.get("credential_required",true)):
  if not credential_reader.is_valid():return {"success":false,"error":"A secure OS-credential-vault adapter has not been configured. Project files cannot store API keys."}
  credential=str(credential_reader.call(provider_id))
  if credential.is_empty():return {"success":false,"error":"The provider credential is missing from the secure vault."}
 var result:=provider.generate(request.duplicate(true),credential,job)
 credential=""
 if job!=null and job.is_cancelled():return {"success":false,"error":"Cancelled. A submitted provider request may already have consumed quota."}
 if not bool(result.get("success",false)):return {"success":false,"error":"Provider generation failed. Check its status in the provider adapter; credentials and raw responses are not logged."}
 var stream:AudioStream=result.get("stream")
 if stream==null or stream.get_length()<=0:return {"success":false,"error":"The provider did not return valid editable audio."}
 # Only an allowlisted, non-secret metadata subset is retained in documents.
 return {"success":true,"stream":stream,"metadata":{"origin":"provider_generated","provider":provider_id,"model":str(request.get("model","")),"task":task,"synthetic_voice":task=="speech","created":Time.get_unix_time_from_system()}}
