extends KiwiAudioProvider
## Optional, opt-in official ElevenLabs speech endpoint. No request on construction.
## https://elevenlabs.io/docs/api-reference/text-to-speech/convert
var transport:=Callable() # Test seam; production always uses verified TLS below.
func descriptor()->Dictionary:
	return {"id":"elevenlabs","label":"ElevenLabs speech (optional)","tasks":["speech"],"models":["eleven_multilingual_v2"],"supports_cancel":true,"credential_required":true}
func generate(request:Dictionary,credential:String,job:RefCounted=null)->Dictionary:
	var text:=str(request.get("prompt",""));var voice:=str(request.get("voice_id",""));var model:=str(request.get("model","eleven_multilingual_v2"))
	if text.strip_edges().is_empty() or text.length()>3000 or voice.is_empty() or voice.length()>128 or credential.is_empty():return {"success":false,"error":"Enter text (up to 3000 characters), a voice ID and a stored credential."}
	if credential.contains("\r") or credential.contains("\n"):return {"success":false,"error":"Invalid provider credential."}
	for character in voice:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return {"success":false,"error":"Invalid voice ID."}
	if not model in descriptor().models:return {"success":false,"error":"Unsupported speech model."}
	var body:=JSON.stringify({"text":text,"model_id":model}).to_utf8_buffer()
	var result:Dictionary=transport.call(voice,body,credential,job) if transport.is_valid() else _request(voice,body,credential,job)
	if not bool(result.get("success",false)):return {"success":false,"error":str(result.get("error","Speech request failed."))}
	var data:PackedByteArray=result.get("data",PackedByteArray())
	if data.is_empty() or data.size()>16*1024*1024:return {"success":false,"error":"Invalid or oversized speech response."}
	var stream:=AudioStreamMP3.load_from_buffer(data)
	if stream==null or stream.get_length()<=0 or stream.get_length()>180:return {"success":false,"error":"Provider audio exceeds the three-minute limit or could not be decoded."}
	return {"success":true,"stream":stream}
func _request(voice:String,body:PackedByteArray,key:String,job:RefCounted)->Dictionary:
	var client:=HTTPClient.new();var error:=client.connect_to_host("api.elevenlabs.io",443,TLSOptions.client())
	if error!=OK:return {"success":false,"error":"Could not initialize the provider connection."}
	var deadline:=Time.get_ticks_msec()+180000;var sent:=false;var data:=PackedByteArray();var status:=0;var problem:=""
	while Time.get_ticks_msec()<deadline:
		if job!=null and job.is_cancelled():problem="Cancelled.";break
		if client.poll()!=OK:problem="Provider connection failed; TLS verification remains enabled.";break
		var state:=client.get_status()
		if state==HTTPClient.STATUS_CONNECTED and not sent:
			error=client.request_raw(HTTPClient.METHOD_POST,"/v1/text-to-speech/"+voice+"?output_format=mp3_44100_128",PackedStringArray(["Content-Type: application/json","Accept: audio/mpeg","xi-api-key: "+key]),body)
			key="";sent=true
			if error!=OK:problem="Could not send the approved speech request.";break
		if client.has_response():
			status=client.get_response_code()
			if status!=200:problem="Provider rejected the request (HTTP %d). Check quota, credential and voice access."%status;break
			if client.get_response_body_length()>16*1024*1024:problem="Provider response exceeds the 16 MiB limit.";break
		if state==HTTPClient.STATUS_BODY:
			data.append_array(client.read_response_body_chunk())
			if data.size()>16*1024*1024:problem="Provider response exceeds the 16 MiB limit.";break
		elif sent and status==200 and state==HTTPClient.STATUS_CONNECTED:
			client.close();return {"success":true,"data":data}
		elif state in [HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,HTTPClient.STATUS_DISCONNECTED]:problem="Provider connection closed or failed.";break
		OS.delay_msec(10)
	client.close()
	return {"success":false,"error":problem if not problem.is_empty() else "Provider request timed out."}
