extends SceneTree
func _initialize()->void:
 var samples:=PackedVector2Array();samples.resize(144000)
 for i in samples.size():samples[i]=Vector2.ONE*sin(TAU*1000*i/48000.0)*0.1
 var first:=KiwiAudioAnalysis.loudness(KiwiAudioSourceCache.to_wav(samples,48000))
 for i in samples.size():samples[i]*=0.5
 var second:=KiwiAudioAnalysis.loudness(KiwiAudioSourceCache.to_wav(samples,48000))
 var silence:=KiwiAudioAnalysis.loudness(KiwiAudioSourceCache.to_wav(PackedVector2Array([Vector2.ZERO,Vector2.ZERO]),48000))
 print(JSON.stringify({"first":first,"half":second,"silence":silence}))
 var ok:=str(first.get("error","")).is_empty() and str(second.get("error","")).is_empty() and absf(float(first.integrated_lufs)-float(second.integrated_lufs)-6.02)<0.1 and absf(float(first.true_peak_db)+20)<0.1 and bool(silence.get("silent",false))
 print("LOUDNESS_TEST ",ok);quit(0 if ok else 1)
