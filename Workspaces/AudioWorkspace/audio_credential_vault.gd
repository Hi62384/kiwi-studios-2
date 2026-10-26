extends RefCounted
## Windows Credential Manager, current Windows user. Never stored in project files.
const Helper=preload("res://Workspaces/AudioWorkspace/audio_optional_process.gd")
static func available()->bool:return OS.get_name()=="Windows"
static func valid_id(id:String)->bool:
	if id.is_empty() or id.length()>64:return false
	for character in id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":return false
	return true
static func request(action:String,id:String,secret:String="",job:RefCounted=null)->Dictionary:
	if not available():return {"success":false,"error":"Windows Credential Manager is unavailable on this platform."}
	if not valid_id(id) or not action in ["read","write","delete"] or secret.length()>1200 or secret.to_utf8_buffer().size()>2400:return {"success":false,"error":"Invalid credential request."}
	var source:=FileAccess.get_file_as_string("res://scripts/actors/audio/windows_credentials.ps1")
	if source.is_empty():return {"success":false,"error":"Could not load the credential helper."}
	# Execute fixed, trusted application code rather than a downloaded script.
	# This needs no ExecutionPolicy bypass or settings change. Only code goes
	# in argv; the credential request goes over the private stdin pipe.
	var encoded:=Marshalls.raw_to_base64(source.to_utf16_buffer())
	var result:=Helper.run("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-EncodedCommand",encoded]),JSON.stringify({"action":action,"id":id,"secret":secret}),job,15,16384)
	if not result.success:return {"success":false,"error":"Windows Credential Manager request failed; no credentials were logged."}
	var response:Variant=JSON.parse_string(result.stdout.strip_edges())
	if not response is Dictionary:return {"success":false,"error":"Invalid credential helper response."}
	return response
static func read(id:String)->String:
	var result:=request("read",id)
	return str(result.get("secret","")) if bool(result.get("success",false)) else ""
