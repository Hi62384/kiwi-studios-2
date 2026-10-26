extends SceneTree
## Explicit opt-in only: this records real microphone and other system audio.
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
	print("PASS " if value else "FAIL ",label)
func run()->void:
	if OS.get_environment("KIWI_TEST_PRIVATE_CAPTURE")!="1":print("SKIP private capture: requires explicit permission and KIWI_TEST_PRIVATE_CAPTURE=1");quit();return
	if DisplayServer.get_name()=="headless":push_error("Private device test requires native audio");quit(1);return
	var recorder:=ActorAudioRecorder.new();recorder.disk_backed=true
	recorder.preferences_override={"record_mic":true,"record_system":true,"record_timeline":false,"monitor_timeline":false,"device":"Default","gain_db":0.,"mono":false};root.add_child(recorder)
	print("Starting user-authorized three-second microphone + system-loopback test; all audio stays local.")
	var error:String=await recorder.start();check(error.is_empty(),"Physical microphone and WASAPI loopback initialization requested")
	if not error.is_empty():print(error);recorder.queue_free();await process_frame;quit(failures);return
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(recorder.bus_name)),"Physical microphone monitoring is muted to prevent feedback")
	var rate:=48000;var samples:=PackedVector2Array();samples.resize(rate*3)
	for index in samples.size():
		var amplitude:=.08*sin(TAU*440.*index/rate)*minf(1.,float(index)/480.)*minf(1.,float(samples.size()-index)/480.)
		samples[index]=Vector2(amplitude,amplitude)
	var player:=AudioStreamPlayer.new();root.add_child(player);player.stream=KiwiAudioSourceCache.to_wav(samples,rate);player.play()
	await create_timer(3.).timeout;player.stop()
	var capture:Dictionary=await recorder.stop_to_files()
	check(str(capture.get("error","")).is_empty(),"Physical capture stops and finalizes without error")
	check(capture.get("paths",[]).size()==2,"Microphone and system inputs remain independent disk sources")
	for source in capture.get("paths",[]):
		var info:=KiwiAudioPCMFile.inspect(source)
		check(str(info.get("error","")).is_empty() and float(info.get("duration",0))>=2.5,"Physical source WAV has valid header and at least 2.5 seconds: "+str(source).get_file())
		var file:=FileAccess.open(source,FileAccess.READ)
		if file==null:continue
		var data:=KiwiAudioPCMFile.read_frames(file,info,0,mini(int(info.get("frames",0)),int(info.get("rate",48000))*4));file.close();var peak:=0.;var energy:=0.;var imaginary:=0.;var real:=0.;var input_rate:=float(info.get("rate",48000))
		for index in data.size():
			var value:=(data[index].x+data[index].y)*.5;peak=maxf(peak,absf(value));energy+=value*value;real+=value*cos(TAU*440.*index/input_rate);imaginary+=value*sin(TAU*440.*index/input_rate)
		var amplitude:=2.*sqrt(real*real+imaginary*imaginary)/maxi(1,data.size())
		print("DEVICE_SIGNAL ",str(source).get_file()," seconds=",info.get("duration",0)," peak=",peak," rms=",sqrt(energy/maxi(1,data.size()))," test_tone_amplitude=",amplitude)
		if str(source).get_file()=="system.wav":check(amplitude>.001,"System loopback contains the known 440 Hz test signal")
		else:check(peak>.0000001,"Physical microphone receives nonzero input (silence/permission failures are not a pass)")
	print("PRIVATE_DEVICE_TAKE_DIRECTORY ",capture.get("directory",""))
	player.queue_free();recorder.queue_free();await process_frame
	print("AUDIO_PRIVATE_DEVICE failures=%d driver=%s"%[failures,AudioServer.get_driver_name()]);quit(failures)
