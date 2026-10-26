extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	var samples := PackedVector2Array(); samples.resize(4800); samples.fill(Vector2(.1,-.2))
	var source := KiwiAudioSourceCache.to_wav(samples,48000)
	var session := KiwiAudioEditSession.new(); session.document=KiwiAudioDocument.from_source(source)
	var actor := session.document.actors[0]; var clip := session.document.clips[0]
	actor.values[&"fade_in"]=0.; actor.values[&"fade_out"]=0.
	var original := source.data
	var result := KiwiAudioRegionEdit.prepare(clip,actor,source,"set_amplitude",Vector2i(100,101),48000,.7,0)
	check(str(result.get("error","")).is_empty(),"A single-channel sample edit prepares successfully")
	var edited: AudioStreamWAV=result.get("stream"); var bytes:=edited.data
	check(bytes.size()==4 and absf(bytes.decode_s16(0)/32768.-.7)<.0001 and absf(bytes.decode_s16(2)/32768.+.2)<.0001,"Numeric amplitude changes only the chosen channel and frame")
	check(source.data==original,"Sample editing does not alter original PCM")
	var applied:=KiwiAudioRegionEdit.apply(session,result)
	check(str(applied.get("error","")).is_empty() and session.document.clips.size()==3,"Sample edit preserves adjacent source windows")
	session.undo(); check(session.document.clips.size()==1 and session.document.actors[0].values.audio==source,"Undo restores the original shared source")
	check(not str(KiwiAudioRegionEdit.prepare(clip,actor,source,"set_amplitude",Vector2i(100,101),48000,2.).get("error","")).is_empty(),"Out-of-range amplitudes are rejected")
	var playback:=KiwiAudioPlayback.new()
	playback.exact_preview_active=true
	check(not playback.meter_supported("track") and playback.meter_supported(),"Rendered playback does not advertise native per-track meters")
	playback.exact_preview_active=false
	check(playback.meter_supported("track"),"Native playback exposes native route meters")
	playback.free()
	print("AUDIO_SAMPLE_VALUE checks=%d failures=%d"%[checks,failures]);quit(failures)
