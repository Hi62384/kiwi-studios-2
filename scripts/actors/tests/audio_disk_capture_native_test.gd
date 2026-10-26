extends SceneTree
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
	print("PASS " if value else "FAIL ",label)
func run()->void:
	if DisplayServer.get_name()=="headless":print("AUDIO_DISK_CAPTURE_NATIVE SKIP: native display/audio driver required");quit(0);return
	var recorder:=ActorAudioRecorder.new();recorder.disk_backed=true
	# Capture ONLY this test's synthetic routed tone. Never open a microphone
	# or system-loopback device; no user's speech or other applications recorded.
	recorder.preferences_override={"record_mic":false,"record_system":false,"record_timeline":true,"monitor_timeline":false,"device":"Default","gain_db":0.,"mono":false};root.add_child(recorder)
	var error:String=await recorder.start();check(error.is_empty(),"Disk timeline capture starts with native audio driver")
	if not error.is_empty():recorder.queue_free();await process_frame;quit(failures);return
	check(recorder.timeline_effect==null and recorder._timeline_writer!=null,"Native recording has no whole-take AudioEffectRecord buffer")
	var data:=PackedVector2Array();data.resize(96000)
	for i in data.size():data[i]=Vector2(.2*sin(TAU*440*i/48000.),.1*sin(TAU*660*i/48000.))
	var player:=AudioStreamPlayer.new();root.add_child(player);player.bus=recorder.timeline_bus_name;player.stream=KiwiAudioSourceCache.to_wav(data,48000);player.play()
	await create_timer(1.25).timeout;player.stop()
	var captured:Dictionary=await recorder.stop_to_files()
	check(str(captured.get("error","")).is_empty() and captured.get("paths",[]).size()==1,"Native Stop produces a recoverable disk WAV")
	if not captured.get("paths",[]).is_empty():
		var info:=KiwiAudioPCMFile.inspect(captured.paths[0]);check(str(info.get("error","")).is_empty() and float(info.get("duration",0))>1.,"Captured WAV has finalized timing/header")
		var file:=FileAccess.open(captured.paths[0],FileAccess.READ);var samples:=KiwiAudioPCMFile.read_frames(file,info,0,mini(48000,int(info.frames)));file.close();var peak:=0.
		for value in samples:peak=maxf(peak,maxf(absf(value.x),absf(value.y)))
		check(peak>.05,"Checkpointed disk capture contains the native routed signal")
	player.queue_free();recorder.queue_free();await process_frame
	print("AUDIO_DISK_CAPTURE_NATIVE failures=%d driver=%s"%[failures,AudioServer.get_driver_name()]);quit(failures)
