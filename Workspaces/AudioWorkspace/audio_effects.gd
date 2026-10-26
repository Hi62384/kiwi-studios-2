class_name KiwiAudioEffects
extends RefCounted
## One catalog. Native previews are explicitly distinct from offline processors.
static func parameter(id: String, label: String, value: float, minimum: float, maximum: float, step: float = 0.01) -> Dictionary:
	return {"id": id, "label": label, "default": value, "min": minimum, "max": maximum, "step": step}

static func catalog() -> Array[Dictionary]:
	return [
		_entry("hq_pitch", "Pitch Bend / Formant-preserving Shift", "Pitch / Time", false, [parameter("semitones","Semitones",0,-24,24,0.1),parameter("preserve","Preserve formants",0,0,1,1)]),
		_entry("formant", "Independent Formant Shift", "Pitch / Time", false, [parameter("semitones","Formant semitones",0,-12,12,0.1)]),
		_entry("time_warp", "Automated Time Warp (fixed clip slot)", "Pitch / Time", false, [parameter("tempo","Speed ratio",1,0.25,4,0.01)]),
		_entry("doppler", "Doppler / Moving Source", "Pitch / Time", false, [parameter("speed","Pass speed (m/s)",35,0,100,0.1),parameter("closest","Closest distance (m)",4,1,50,0.1),parameter("travel","Half travel (m)",100,10,300,1),parameter("pass_time","Pass time (source s)",2,0,3600,0.01),parameter("reverse","Right to left",0,0,1,1),parameter("attenuation","Distance attenuation",1,0,1),parameter("width","Stereo travel",0.7,0,1),parameter("mix","Wet",1,0,1)]),
		_entry("audio_fm", "Audio-rate Frequency Modulation", "Modulation", false, [parameter("rate","Modulator (Hz)",120,20,2000,1),parameter("depth","Depth",0.15,0,1)]),
		_entry("distance", "Distance Attenuation / Air Loss", "Stereo", false, [parameter("distance","Distance (m)",8,1,100,0.1),parameter("reference","Reference (m)",1,1,10,0.1),parameter("air","Air absorption",0.5,0,1)]),
		_entry("convolution", "Convolution Reverb (own impulse)", "Space", false, [parameter("mix","Wet",0.3,0,1),parameter("length","Maximum IR (s)",3,0.1,20,0.1)]),
		_entry("plate", "Diffuse Plate Model", "Space", false, [parameter("decay","Decay (s)",2,0.1,8,0.1),parameter("damping","Damping",0.5,0,1),parameter("mix","Wet",0.3,0,1)]),
		_entry("spring", "Dispersive Spring Model", "Space", false, [parameter("decay","Decay (s)",1.5,0.1,8,0.1),parameter("damping","Damping",0.5,0,1),parameter("tension","Tension",1,0.5,2),parameter("mix","Wet",0.35,0,1)]),
		_entry("pingpong", "Ping-Pong Echo", "Space", false, [parameter("time","Delay (s)",0.25,0.01,1.5),parameter("feedback","Feedback",0.45,0,0.85),parameter("mix","Wet",0.3,0,1)]),
		_entry("multiband", "Three-band Compressor", "Dynamics", false, [parameter("threshold", "Threshold (dB)",-18,-50,-3,0.1),parameter("ratio","Ratio",3,1,10),parameter("low","Low split (Hz)",200,80,800,1),parameter("high","High split (Hz)",3000,1500,6000,1),parameter("attack","Attack (ms)",10,0.1,100),parameter("release","Release (ms)",150,20,1000),parameter("makeup","Makeup (dB)",0,0,12)]),
		_entry("graphic_eq", "Eight-band Graphic EQ", "Filter / EQ", false, [parameter("b63","63 Hz",0,-15,15,0.1),parameter("b125","125 Hz",0,-15,15,0.1),parameter("b250","250 Hz",0,-15,15,0.1),parameter("b500","500 Hz",0,-15,15,0.1),parameter("b1000","1 kHz",0,-15,15,0.1),parameter("b2000","2 kHz",0,-15,15,0.1),parameter("b4000","4 kHz",0,-15,15,0.1),parameter("b8000","8 kHz",0,-15,15,0.1)]),
		_entry("early_reflections", "Early Reflections", "Space", false, [parameter("size","Size",0.5,0.05,1),parameter("mix","Wet",0.25,0,1)]),
		_entry("stereo_delay", "Stereo Channel Delay", "Space", false, [parameter("left","Left delay (ms)",20,0,500,1),parameter("right","Right delay (ms)",65,0,500,1)]),
		_entry("frequency_shift", "Frequency Shifter", "Modulation", false, [parameter("shift","Shift (Hz)",30,-2000,2000,1)]),
		_entry("tube", "Asymmetric Tube-style Drive", "Distortion", false, [parameter("drive","Drive",3,1,12),parameter("bias","Asymmetry",0.1,0,0.5),parameter("output","Output (dB)",-6,-24,0,0.1)]),
		_entry("tape", "Tape-style Color / Wow", "Distortion", false, [parameter("drive","Drive",2,1,8),parameter("cutoff","High rolloff (Hz)",12000,2000,18000,1),parameter("wow","Wow depth",0.03,0,0.5),parameter("rate","Wow rate (Hz)",0.5,0.1,4),parameter("output","Output (dB)",-6,-24,0,0.1)]),
		_entry("gain", "Gain", "Dynamics", true, [parameter("db", "Gain (dB)", 0, -60, 24, 0.1)]),
		_entry("normalize", "Loudness Normalize", "Dynamics", false, [parameter("lufs", "Target LUFS", -16, -30, -8, 0.1), parameter("peak", "True peak (dB)", -1, -9, -0.1, 0.1)]),
		_entry("limiter", "Peak Limiter", "Dynamics", true, [parameter("ceiling", "Ceiling (dB)", -1, -24, 0, 0.1), parameter("release", "Release (s)", 0.1, 0.01, 3)]),
		_entry("compressor", "Compressor", "Dynamics", true, [parameter("threshold", "Threshold (dB)", -18, -60, 0, 0.1), parameter("ratio", "Ratio", 4, 1, 20), parameter("attack", "Attack (ms)", 10, 0.02, 200), parameter("release", "Release (ms)", 180, 20, 2000), parameter("makeup", "Makeup (dB)", 0, 0, 18, 0.1)]),
		_entry("gate", "Gate / Expander", "Dynamics", false, [parameter("threshold", "Threshold (dB)", -40, -80, -1, 0.1), parameter("ratio", "Ratio", 4, 1, 20), parameter("attack", "Attack (ms)", 5, 0.1, 200), parameter("release", "Release (ms)", 150, 10, 2000)]),
		_entry("deesser", "De-Esser", "Dynamics", false, [parameter("intensity", "Intensity", 0.5, 0, 1), parameter("amount", "Reduction", 0.5, 0, 1)]),
		_entry("leveler", "Automatic Leveler", "Dynamics", false, [parameter("strength", "Maximum gain", 5, 1, 20), parameter("window", "Window (ms)", 500, 100, 2000, 10)]),
		_entry("transient", "Transient Emphasis", "Dynamics", false, [parameter("amount", "Emphasis", 2, 0, 8)]),
		_entry("lowpass", "Low Pass", "Filter / EQ", true, [parameter("frequency", "Cutoff (Hz)", 6000, 20, 20000, 1), parameter("q", "Resonance", 0.707, 0.1, 10)]),
		_entry("highpass", "High Pass", "Filter / EQ", true, [parameter("frequency", "Cutoff (Hz)", 80, 20, 18000, 1), parameter("q", "Resonance", 0.707, 0.1, 10)]),
		_entry("bandpass", "Band Pass", "Filter / EQ", true, [parameter("frequency", "Center (Hz)", 1200, 20, 18000, 1), parameter("q", "Q", 1, 0.1, 10)]),
		_entry("notch", "Notch / Hum", "Filter / EQ", true, [parameter("frequency", "Center (Hz)", 60, 20, 18000, 1), parameter("q", "Q", 10, 0.1, 30)]),
		_entry("eq", "Parametric EQ", "Filter / EQ", false, [parameter("frequency", "Center (Hz)", 1500, 20, 20000, 1), parameter("q", "Q", 1, 0.1, 10), parameter("db", "Gain (dB)", 3, -24, 24, 0.1)]),
		_entry("low_shelf", "Low Shelf", "Filter / EQ", false, [parameter("frequency", "Frequency (Hz)", 150, 20, 2000, 1), parameter("db", "Gain (dB)", 3, -24, 24, 0.1)]),
		_entry("high_shelf", "High Shelf", "Filter / EQ", false, [parameter("frequency", "Frequency (Hz)", 5000, 500, 20000, 1), parameter("db", "Gain (dB)", 3, -24, 24, 0.1)]),
		_entry("telephone", "Telephone", "Filter / EQ", false, [parameter("low", "Low cut (Hz)", 300, 80, 1500, 1), parameter("high", "High cut (Hz)", 3400, 1800, 9000, 1)]),
		_entry("dynamic_eq", "Dynamic EQ", "Filter / EQ", false, [parameter("frequency", "Center (Hz)", 3500, 40, 18000, 1), parameter("threshold", "Detection", 3, 0, 20), parameter("ratio", "Ratio", 2, 1, 10)]),
		_entry("delay", "Delay / Echo", "Space", true, [parameter("time", "Delay (s)", 0.25, 0.001, 1.5), parameter("feedback", "Feedback", 0.35, 0, 0.85), parameter("mix", "Wet", 0.3, 0, 1)]),
		_entry("reverb", "Algorithmic Room / Hall", "Space", true, [parameter("size", "Room size", 0.6, 0.05, 1), parameter("damping", "Damping", 0.5, 0, 1), parameter("mix", "Wet", 0.25, 0, 1)]),
		_entry("chorus", "Chorus", "Modulation", true, [parameter("rate", "Rate (Hz)", 0.8, 0.05, 8), parameter("depth", "Depth (ms)", 4, 0.1, 10), parameter("mix", "Wet", 0.3, 0, 1)]),
		_entry("flanger", "Flanger", "Modulation", false, [parameter("rate", "Rate (Hz)", 0.3, 0.1, 5), parameter("depth", "Depth (ms)", 3, 0, 10), parameter("feedback", "Feedback", 0.4, -0.9, 0.9)]),
		_entry("phaser", "Phaser", "Modulation", true, [parameter("rate", "Rate (Hz)", 0.5, 0.1, 2), parameter("depth", "Depth", 0.6, 0.1, 1)]),
		_entry("tremolo", "Tremolo", "Modulation", false, [parameter("rate", "Rate (Hz)", 4, 0.1, 20), parameter("depth", "Depth", 0.5, 0, 1)]),
		_entry("vibrato", "Vibrato", "Modulation", false, [parameter("rate", "Rate (Hz)", 5, 0.1, 20), parameter("depth", "Depth", 0.4, 0, 1)]),
		_entry("ring", "Ring / Robot", "Modulation", false, [parameter("frequency", "Carrier (Hz)", 65, 1, 2000, 1), parameter("mix", "Wet", 0.8, 0, 1)]),
		_entry("autopan", "Auto Pan", "Stereo", false, [parameter("rate", "Rate (Hz)", 0.5, 0.05, 10), parameter("depth", "Width", 0.8, 0, 1)]),
		_entry("saturate", "Saturation / Overdrive", "Distortion", true, [parameter("drive", "Drive", 0.35, 0, 1), parameter("output", "Output (dB)", -6, -30, 12, 0.1)]),
		_entry("hardclip", "Hard Clipping", "Distortion", true, [parameter("drive", "Drive (dB)", 6, 0, 30, 0.1), parameter("output", "Output (dB)", -6, -30, 0, 0.1)]),
		_entry("bitcrusher", "Bitcrusher", "Distortion", false, [parameter("bits", "Bit depth", 8, 2, 16, 1), parameter("reduction", "Rate reduction", 1, 1, 32, 1)]),
		_entry("wavefold", "Wavefolding", "Distortion", false, [parameter("drive", "Fold drive", 3, 1, 12), parameter("output", "Output (dB)", -6, -30, 0, 0.1)]),
		_entry("pitch", "Pitch Shift", "Pitch / Time", true, [parameter("semitones", "Semitones", 0, -24, 24, 0.1)]),
		_entry("stretch", "Time Stretch (fixed clip slot)", "Pitch / Time", false, [parameter("factor", "Duration ratio", 1.25, 0.25, 4)]),
		_entry("reverse", "Reverse", "Pitch / Time", false, []),
		_entry("stereo_width", "Stereo Width / Mono", "Stereo", true, [parameter("width", "Width", 1.4, 0, 4)]),
		_entry("pan", "Stereo Balance", "Stereo", true, [parameter("pan", "Pan", 0, -1, 1)]),
		_entry("noise_reduce", "Spectral Noise Reduction", "Restoration", false, [parameter("reduction", "Reduction (dB)", 12, 0.01, 40, 0.1), parameter("floor", "Noise floor (dB)", -45, -80, -20, 0.1)]),
		_entry("dereverb", "Room Decay Suppression", "Restoration", false, [parameter("strength","Strength",.6,0,1),parameter("decay","Estimated RT60 (s)",.6,.05,2.,.01),parameter("floor","Maximum residual floor (dB)",-12,-30,0,.1)]),
		_entry("hum_remove", "Harmonic Hum Removal", "Restoration", false, [parameter("frequency", "Mains frequency (Hz)", 60, 40, 100, 1), parameter("harmonics", "Harmonics", 4, 1, 8, 1)]),
		_entry("declick", "Click / Pop Repair", "Restoration", false, [parameter("threshold", "Threshold", 2, 1, 20), parameter("window", "Window (ms)", 30, 10, 100, 1)]),
		_entry("declip", "Clipping Repair", "Restoration", false, [parameter("threshold", "Threshold", 10, 1, 40)]),
		_entry("breath", "Quiet Passage Expansion", "Restoration", false, [parameter("threshold", "Floor (dB)", -35, -70, -10, 0.1), parameter("ratio", "Expansion", 2, 1, 8)])
	]

static func _entry(id: String, label: String, category: String, realtime: bool, parameters: Array) -> Dictionary:
	if id=="dereverb":return {"id":id,"label":label,"category":category,"realtime":false,"parameters":parameters,"description":"Offline multiband decay suppression, not perfect dry-speech reconstruction. Protects onsets/sustained energy and attenuates falling tails using estimated RT60. May reduce intended musical tails; compare/bypass before baking. Static controls, 64 MiB stage and 60-second processing limits."}
	if id == "breath":
		return {"id": id, "label": label, "category": category, "realtime": false, "parameters": parameters,
			"description": "Offline level-based downward expansion of quiet passages. It can reduce low-level room noise or breaths, but cannot classify breaths, remove reverberation or separate speech from noise. Preview before applying; quiet speech can also be reduced."}
	if id in ["hq_pitch","formant","time_warp"]:label+=" (Rubber Band)"
	if id == "doppler":
		return {"id": id, "label": label, "category": category, "realtime": false, "parameters": parameters,
			"description": "Offline moving-source propagation delay at 343 m/s, with an eased subsonic pass. Static controls; clip time starts at the clip, track/master time at the timeline. Wet audio keeps its acoustic arrival delay; dry stays aligned. Resampling rolls off high frequencies to limit aliasing. No sonic boom, reflections, air loss or HRTF."}
	return {"id": id, "label": label, "category": category, "realtime": realtime, "parameters": parameters,
		"description": ("Native approximation (compressor attack capped at 2 ms); render preview for exact offline result" if id == "compressor" else "Native approximation; render preview to hear the exact offline result") if realtime else "Offline processor; render preview to hear exact result"}

static func definition(id: String) -> Dictionary:
	for entry in catalog():
		if entry.id == id: return entry
	return {}

static func create(id: String) -> Dictionary:
	var entry := definition(id)
	if entry.is_empty(): return {}
	var result := {"id": ActorData.new_id(), "type": id, "enabled": true, "parameters": {}, "automation": {}}
	for parameter_info in entry.parameters: result.parameters[parameter_info.id] = parameter_info.default
	return result

static func native(effect: Dictionary) -> AudioEffect:
	if not bool(effect.get("enabled", true)): return null
	var p: Dictionary = effect.get("parameters", {})
	var kind := str(effect.get("type", ""))
	match kind:
		"gain":
			var fx := AudioEffectAmplify.new(); fx.volume_db = float(p.get("db", 0)); return fx
		"limiter":
			var fx := AudioEffectHardLimiter.new(); fx.ceiling_db = float(p.get("ceiling", -1)); fx.release = float(p.get("release", 0.1)); return fx
		"compressor":
			var fx := AudioEffectCompressor.new()
			fx.threshold = float(p.get("threshold", -18)); fx.ratio = float(p.get("ratio", 4))
			fx.attack_us = clampf(float(p.get("attack", 10)) * 1000, 20, 2000)
			fx.release_ms = float(p.get("release", 180)); fx.gain = float(p.get("makeup", 0))
			if p.has("sidechain"): fx.sidechain = StringName(p.sidechain)
			return fx
		"lowpass", "highpass", "bandpass", "notch":
			var fx: AudioEffectFilter
			match kind:
				"lowpass": fx = AudioEffectLowPassFilter.new()
				"highpass": fx = AudioEffectHighPassFilter.new()
				"bandpass": fx = AudioEffectBandPassFilter.new()
				_: fx = AudioEffectNotchFilter.new()
			fx.cutoff_hz = float(p.get("frequency", 1000)); fx.resonance = clampf(float(p.get("q", 0.707)), 0, 1)
			return fx
		"delay":
			var fx := AudioEffectDelay.new()
			var wet := float(p.get("mix", 0.3))
			fx.dry = 1.0 - wet * 0.3; fx.tap1_delay_ms = float(p.get("time", 0.25)) * 1000
			fx.tap1_level_db = linear_to_db(maxf(0.00001, wet)); fx.tap1_pan = 0; fx.tap2_active = false
			fx.feedback_active = float(p.get("feedback", 0.35)) > 0
			fx.feedback_delay_ms = fx.tap1_delay_ms
			fx.feedback_level_db = linear_to_db(maxf(0.00001, float(p.get("feedback", 0.35))))
			return fx
		"reverb":
			var fx := AudioEffectReverb.new()
			fx.room_size = float(p.get("size", 0.6)); fx.damping = float(p.get("damping", 0.5))
			fx.wet = float(p.get("mix", 0.25)); fx.dry = 1.0
			return fx
		"chorus":
			var fx := AudioEffectChorus.new()
			fx.voice_count = 2; fx.wet = float(p.get("mix", 0.3)); fx.dry = 1.0
			for voice in 2:
				fx.set_voice_rate_hz(voice, float(p.get("rate", 0.8)) * (1.0 + voice * 0.13))
				fx.set_voice_depth_ms(voice, float(p.get("depth", 4))); fx.set_voice_delay_ms(voice, 12 + voice * 7)
				fx.set_voice_pan(voice, -0.5 if voice == 0 else 0.5)
			return fx
		"phaser":
			var fx := AudioEffectPhaser.new(); fx.rate_hz = float(p.get("rate", 0.5)); fx.depth = float(p.get("depth", 0.6)); return fx
		"saturate", "hardclip":
			var fx := AudioEffectDistortion.new()
			fx.mode = AudioEffectDistortion.MODE_ATAN if kind == "saturate" else AudioEffectDistortion.MODE_CLIP
			fx.drive = float(p.get("drive", 0.35)) if kind == "saturate" else 0.0
			fx.pre_gain = 12.0 * fx.drive if kind == "saturate" else float(p.get("drive", 6))
			fx.post_gain = float(p.get("output", -6)); return fx
		"pitch":
			var fx := AudioEffectPitchShift.new(); fx.pitch_scale = pow(2.0, float(p.get("semitones", 0)) / 12.0); return fx
		"stereo_width":
			var fx := AudioEffectStereoEnhance.new(); fx.pan_pullout = float(p.get("width", 1.4)); return fx
		"pan":
			var fx := AudioEffectPanner.new(); fx.pan = float(p.get("pan", 0)); return fx
	return null

static func offline_filter(effect: Dictionary, rate: int = 44100) -> String:
	if not bool(effect.get("enabled", true)): return ""
	var p: Dictionary = effect.get("parameters", {})
	var kind := str(effect.get("type", ""))
	match kind:
		"doppler":
			# Requires KiwiAudioRenderer's ordered staged-PCM path. There is no
			# invented FFmpeg 'doppler' filter and no live panner substitute.
			return ""
		"hq_pitch":return "rubberband=pitch=%s:formant=%s:pitchq=quality:channels=together"%[number(pow(2.0,float(p.get("semitones",0))/12)),"preserved" if float(p.get("preserve",0))>=0.5 else "shifted"]
		"formant":
			var ratio:=pow(2.0,float(p.get("semitones",0))/12)
			return "rubberband=pitch=%s:formant=preserved:pitchq=quality:channels=together,asetrate=%s,aresample=%d,%s"%[number(1/ratio),number(rate*ratio),rate,tempo_filter(1/ratio)]
		"time_warp":return "rubberband=tempo=%s:pitch=1:channels=together"%number(p.get("tempo",1))
		"audio_fm":return "vibrato=f=%s:d=%s"%[number(p.get("rate",120)),number(p.get("depth",0.15))]
		"distance":
			var distance:=maxf(1,float(p.get("distance",8)));var reference:=maxf(1,float(p.get("reference",1)))
			return "volume=%s,lowpass=f=%s"%[number(minf(1,reference/distance)),number(minf(rate*0.45,20000/(1+float(p.get("air",0.5))*maxf(0,distance-reference)*0.08)))]
		"multiband":
			var threshold:=float(p.get("threshold",-18));var ratio:=maxf(1,float(p.get("ratio",3)))
			var transfer:="-90/-90,%s/%s,0/%s"%[number(threshold),number(threshold),number(threshold*(1-1/ratio))]
			var envelope:="%s,%s 6 %s"%[number(float(p.get("attack",10))/1000),number(float(p.get("release",150))/1000),transfer]
			return "mcompand=args='%s %s | %s %s | %s %s',volume=%sdB"%[envelope,number(minf(rate*0.1,float(p.get("low",200)))),envelope,number(minf(rate*0.4,float(p.get("high",3000)))),envelope,number(minf(22000,rate*0.49)),number(p.get("makeup",0))]
		"graphic_eq":
			var filters:=PackedStringArray()
			for frequency in [63,125,250,500,1000,2000,4000,8000]:filters.append("equalizer=f=%s:t=o:w=1:g=%s"%[number(minf(rate*0.45,frequency)),number(p.get("b"+str(frequency),0))])
			return ",".join(filters)
		"early_reflections":
			var wet:=float(p.get("mix",0.25))
			if wet<=0:return ""
			var size:=float(p.get("size",0.5));var times:=PackedStringArray();var gains:=PackedStringArray()
			for i in 4:times.append(number([17,29,43,67][i]*(0.5+size)));gains.append(number(wet*[0.5,0.35,0.23,0.15][i]))
			return "aecho=1:1:%s:%s"%["|".join(times),"|".join(gains)]
		"stereo_delay":return "adelay=%s|%s"%[number(p.get("left",20)),number(p.get("right",65))]
		"frequency_shift":return "afreqshift=shift=%s:order=12"%number(p.get("shift",30))
		"tube":
			var drive:=number(p.get("drive",3));var bias:=number(p.get("bias",0.1))
			var expr:="(atan((val(CH)+%s)*%s)-atan(%s*%s))"%[bias,drive,bias,drive]
			return "aeval='%s|%s',highpass=f=15,volume=%sdB"%[expr.replace("CH","0"),expr.replace("CH","1"),number(p.get("output",-6))]
		"tape":return "volume=%s,asoftclip=type=tanh,lowpass=f=%s,vibrato=f=%s:d=%s,volume=%sdB"%[number(p.get("drive",2)),number(minf(rate*0.45,float(p.get("cutoff",12000)))),number(p.get("rate",0.5)),number(p.get("wow",0.03)),number(p.get("output",-6))]
		"gain": return "volume=%sdB" % number(p.get("db", 0))
		"normalize": return "loudnorm=I=%s:TP=%s:LRA=11,aresample=%d" % [number(p.get("lufs", -16)), number(p.get("peak", -1)), rate]
		"limiter": return "alimiter=limit=%s:attack=5:release=%s:level=false:latency=true" % [number(db_to_linear(float(p.get("ceiling", -1)))), number(float(p.get("release", 0.1)) * 1000)]
		"compressor": return "acompressor=threshold=%s:ratio=%s:attack=%s:release=%s:makeup=%s" % [number(db_to_linear(float(p.get("threshold", -18)))), number(p.get("ratio", 4)), number(p.get("attack", 10)), number(p.get("release", 180)), number(db_to_linear(float(p.get("makeup", 0))))]
		"gate", "breath": return "agate=threshold=%s:ratio=%s:attack=%s:release=%s" % [number(db_to_linear(float(p.get("threshold", -40)))), number(p.get("ratio", 4)), number(p.get("attack", 5)), number(p.get("release", 150))]
		"deesser": return "deesser=i=%s:m=%s" % [number(p.get("intensity", 0.5)), number(p.get("amount", 0.5))]
		"leveler": return "dynaudnorm=f=%s:g=31:m=%s" % [number(p.get("window", 500)), number(p.get("strength", 5))]
		"transient": return "crystalizer=i=%s" % number(p.get("amount", 2))
		"lowpass", "highpass": return "%s=f=%s:t=q:w=%s" % [kind, number(minf(rate * 0.45, float(p.get("frequency", 1000)))), number(p.get("q", 0.707))]
		"bandpass", "notch": return "%s=f=%s:t=q:w=%s" % ["bandreject" if kind == "notch" else "bandpass", number(minf(rate * 0.45, float(p.get("frequency", 1000)))), number(p.get("q", 1))]
		"eq": return "equalizer=f=%s:t=q:w=%s:g=%s" % [number(p.get("frequency", 1500)), number(p.get("q", 1)), number(p.get("db", 3))]
		"low_shelf", "high_shelf": return "%s=f=%s:g=%s" % ["bass" if kind == "low_shelf" else "treble", number(p.get("frequency", 150)), number(p.get("db", 3))]
		"telephone": return "highpass=f=%s,lowpass=f=%s" % [number(p.get("low", 300)), number(p.get("high", 3400))]
		"dynamic_eq": return "adynamicequalizer=dfrequency=%s:tfrequency=%s:threshold=%s:ratio=%s" % [number(p.get("frequency", 3500)), number(p.get("frequency", 3500)), number(p.get("threshold", 3)), number(p.get("ratio", 2))]
		"delay":
			var wet := clampf(float(p.get("mix", 0.3)), 0, 1)
			if wet <= 0: return ""
			var delays := PackedStringArray(); var gains := PackedStringArray()
			var feedback := clampf(float(p.get("feedback", 0.35)), 0, 0.85)
			for tap in 8:
				var decay := wet * pow(feedback, tap)
				if decay < 0.00000001: break
				delays.append(number(float(p.get("time", 0.25)) * 1000 * (tap + 1)))
				gains.append(number(decay))
			return "aecho=1:1:%s:%s" % ["|".join(delays), "|".join(gains)]
		"reverb":
			if float(p.get("mix", 0.25)) <= 0: return ""
			# Dense, decorrelated early/late reflections; native Godot preview uses its own room algorithm.
			var times := PackedStringArray(); var gains := PackedStringArray()
			var size := float(p.get("size", 0.6)); var damp := float(p.get("damping", 0.5))
			for tap in 32:
				var time := 19.0 + (tap * tap * 1.71 + tap * 13.7) * (0.2 + size)
				times.append(number(time))
				gains.append(number(float(p.get("mix", 0.25)) * exp(-time / (250 + size * 1100)) * 0.35))
			return "aecho=1:1:%s:%s,lowpass=f=%s" % ["|".join(times), "|".join(gains), number(19000 - damp * 5000)]
		"chorus":
			var wet := clampf(float(p.get("mix", 0.3)), 0, 1)
			if wet <= 0: return ""
			return "chorus=1:1:40|53:%s|%s:%s|%s:%s|%s" % [number(wet * 0.5), number(wet * 0.5), number(p.get("rate", 0.8)), number(float(p.get("rate", 0.8)) * 1.13), number(p.get("depth", 4)), number(float(p.get("depth", 4)) * 0.8)]
		"flanger": return "flanger=delay=0:depth=%s:regen=%s:speed=%s" % [number(p.get("depth", 3)), number(float(p.get("feedback", 0.4)) * 90), number(p.get("rate", 0.3))]
		"phaser": return "aphaser=0.6:0.7:3:%s:%s:t" % [number(float(p.get("depth", 0.6)) * 0.9), number(clampf(float(p.get("rate", 0.5)), 0.1, 2))]
		"tremolo", "vibrato": return "%s=f=%s:d=%s" % [kind, number(p.get("rate", 4)), number(p.get("depth", 0.5))]
		"ring":
			var expr := "val(CH)*(1-%s+%s*sin(2*PI*%s*t))" % [number(p.get("mix", 0.8)), number(p.get("mix", 0.8)), number(p.get("frequency", 65))]
			return "aeval='%s|%s'" % [expr.replace("CH", "0"), expr.replace("CH", "1")]
		"autopan":
			var phase := "%s*sin(2*PI*%s*t)" % [number(p.get("depth", 0.8)), number(clampf(float(p.get("rate", 0.5)), 0.05, 10))]
			return "aeval='val(0)*sqrt(0.5*(1-(%s)))|val(1)*sqrt(0.5*(1+(%s)))'" % [phase, phase]
		"saturate": return "volume=%s,asoftclip=type=tanh,volume=%sdB" % [number(1 + float(p.get("drive", 0.35)) * 8), number(p.get("output", -6))]
		"hardclip": return "volume=%sdB,asoftclip=type=hard,volume=%sdB" % [number(p.get("drive", 6)), number(p.get("output", -6))]
		"bitcrusher": return "acrusher=bits=%s:samples=%s" % [number(p.get("bits", 8)), number(p.get("reduction", 1))]
		"wavefold":
			var expr := "asin(sin(val(CH)*%s*PI/2))*2/PI" % number(p.get("drive", 3))
			return "aeval='%s|%s',volume=%sdB" % [expr.replace("CH", "0"), expr.replace("CH", "1"), number(p.get("output", -6))]
		"pitch":
			var ratio := pow(2.0, float(p.get("semitones", 0)) / 12.0)
			return "asetrate=%s,aresample=%d,%s" % [number(rate * ratio), rate, tempo_filter(1.0 / ratio)]
		"stretch": return tempo_filter(1.0 / maxf(0.05, float(p.get("factor", 1.25))))
		"reverse": return "areverse"
		"stereo_width":
			var width := float(p.get("width", 1.4))
			return "pan=stereo|c0=%s*c0+%s*c1|c1=%s*c1+%s*c0" % [number((1+width)*0.5), number((1-width)*0.5), number((1+width)*0.5), number((1-width)*0.5)]
		"pan": return pan_filter(float(p.get("pan", 0)))
		"noise_reduce":
			var bands:Variant=p.get("noise_profile",[])
			var profile:=""
			if bands is Array and bands.size()==15:
				var values:=PackedStringArray()
				for value in bands:values.append(number(clampf(float(value),-24,24)))
				profile=":nt=c:bn='"+" ".join(values)+"'"
			return "afftdn=nr=%s:nf=%s:tn=%d:gs=5%s" % [number(p.get("reduction",12)),number(p.get("floor",-45)),1 if profile.is_empty() else 0,profile]
		"hum_remove":
			var filters := PackedStringArray()
			for harmonic in int(p.get("harmonics", 4)): filters.append("bandreject=f=%s:t=q:w=20" % number(float(p.get("frequency", 60)) * (harmonic + 1)))
			return ",".join(filters)
		"declick": return "adeclick=t=%s:w=%s" % [number(p.get("threshold", 2)), number(p.get("window", 30))]
		"declip": return "adeclip=t=%s" % number(p.get("threshold", 10))
	return ""

static func number(value: Variant) -> String:
	var x := float(value)
	return "%.8f" % (x if is_finite(x) else 0.0)

static func tempo_filter(speed: float) -> String:
	var filters := PackedStringArray()
	speed = clampf(speed, 0.015625, 64)
	while speed < 0.5:
		filters.append("atempo=0.5"); speed *= 2
	while speed > 2:
		filters.append("atempo=2"); speed *= 0.5
	filters.append("atempo=" + number(speed))
	return ",".join(filters)

static func pan_filter(pan: float) -> String:
	pan = clampf(pan, -1, 1)
	return "pan=stereo|c0=%s*c0|c1=%s*c1" % [number(minf(1, 1 - pan)), number(minf(1, 1 + pan))]

static func chain(effects: Array, rate: int = 44100, context: String = "effect") -> String:
	var filters := PackedStringArray()
	for index in effects.size():
		var effect:Dictionary=effects[index]
		var filter := rendered_filter(effect,rate,context+str(index))
		if not filter.is_empty(): filters.append(filter)
	return ",".join(filters)

static func tail_seconds(effects: Array) -> float:
	var tail := 0.0
	for effect in effects:
		if not bool(effect.get("enabled", true)): continue
		var p: Dictionary = effect.get("parameters", {})
		if str(effect.get("type", "")) == "doppler": tail += KiwiAudioDoppler.tail_seconds(p)
		if effect.type in ["convolution","plate","spring","pingpong"] and float(p.get("mix",0.3))>0:tail+=KiwiAudioImpulse.duration(str(effect.type),p)
		if effect.type == "early_reflections" and float(p.get("mix",0.25))>0: tail += 0.067*(0.5+float(p.get("size",0.5)))
		if effect.type == "stereo_delay": tail += maxf(float(p.get("left",20)),float(p.get("right",65)))/1000
		if effect.type == "delay" and float(p.get("mix", 0.3)) > 0: tail += float(p.get("time", 0.25)) * (1 if float(p.get("feedback", 0.35)) <= 0 else 8)
		if effect.type == "reverb" and float(p.get("mix", 0.25)) > 0: tail += 4.0 * float(p.get("size", 0.6)) + 0.5
	return minf(tail, 30.0)


static func update_native_properties(target:AudioEffect, source:AudioEffect)->void:
	# Preserve the running DSP instance/tail while editing resource parameters.
	for property in source.get_property_list():
		var name:=str(property.name)
		if (int(property.usage)&PROPERTY_USAGE_STORAGE)!=0 and name not in ["resource_local_to_scene","resource_name","script"]:
			var value:Variant=source.get(name)
			if target.get(name)!=value:target.set(name,value)

static func automation_commands(type:String)->Dictionary:
	match type:
		"gain":return {"db":"volume"}
		"hq_pitch":return {"semitones":"pitch"}
		"time_warp":return {"tempo":"tempo"}
		"lowpass","highpass","bandpass","notch":return {"frequency":"frequency","q":"width"}
		"eq":return {"frequency":"frequency","q":"width","db":"gain"}
		"low_shelf","high_shelf":return {"frequency":"frequency","db":"gain"}
		"compressor":return {"threshold":"threshold","ratio":"ratio","makeup":"makeup"}
		"gate","breath":return {"ratio":"ratio"}
		"frequency_shift":return {"shift":"shift"}
		"bitcrusher":return {"bits":"bits","reduction":"samples"}
		"noise_reduce":return {"reduction":"noise_reduction","floor":"noise_floor"}
	return {}

static func evaluated_stack(stack:Array,time:float)->Array:
	var output:Array=[]
	for original in stack:
		var effect:Dictionary=original.duplicate(true)
		for parameter_name in effect.get("automation",{}):
			var points:Array=effect.automation[parameter_name]
			if not points.is_empty():effect.parameters[parameter_name]=KiwiAudioEditSession.automation_value(points,time,float(effect.parameters.get(parameter_name,0)))
		output.append(effect)
	return output

static func rendered_filter(effect:Dictionary,rate:int,context:String)->String:
	var filter:=automated_filter(effect,rate,offline_filter(effect,rate),context)
	if not filter.is_empty() and str(effect.get("type",""))=="noise_reduce":
		# FFmpeg afftdn uses a 3-hop window and advances one hop; compensate its
		# two-hop signal latency rather than shifting dialogue against the timeline.
		# Source: FFmpeg libavfilter/af_afftdn.c (sample_advance = sample_rate / 80).
		var latency:=2*int(rate/80)
		filter="apad=pad_len=%d,%s,atrim=start_sample=%d,asetpts=PTS-STARTPTS"%[latency,filter,latency]
	return filter

static func automated_filter(effect:Dictionary,rate:int,filter:String,context:String)->String:
	if filter.is_empty() or effect.get("automation",{}).is_empty():return filter
	if str(effect.type)=="hq_pitch":filter=filter.replace("pitchq=quality","pitchq=consistency")
	var mapping:=automation_commands(str(effect.type))
	var first_filter:=filter.get_slice("=",0)
	var target:=first_filter+"@kiwi_"+context.sha256_text().substr(0,12)
	var commands:PackedStringArray=[]
	var fields:Dictionary={}
	for field in definition(str(effect.type)).get("parameters",[]):fields[str(field.id)]=field
	for key in effect.automation:
		if not mapping.has(str(key)):continue
		var points:Array=effect.automation[key]
		if points.is_empty():continue
		var duration:=0.0
		for point in points:duration=maxf(duration,float(point.time))
		var interval:=maxf(0.02,duration/5000.0)
		var count:=maxi(1,ceili(duration/interval))
		var ordered:Array=points.duplicate(true);ordered.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
		var previous_argument:=""
		for step in count+1:
			var time:=minf(duration,step*interval)
			var value:=KiwiAudioEditSession.automation_value(ordered,time,float(effect.parameters.get(key,0)))
			var field:Dictionary=fields.get(str(key),{"min":-100000,"max":100000})
			value=clampf(value,float(field.min),float(field.max))
			if str(key)=="frequency":value=minf(value,rate*0.45)
			var argument:=number(value)
			if str(key) in ["threshold","makeup"] and str(effect.type) in ["compressor","gate","breath"]:argument=number(db_to_linear(value))
			if str(effect.type)=="gain":argument+="dB"
			if str(effect.type)=="hq_pitch" and str(key)=="semitones":argument=number(pow(2.0,value/12))
			if argument!=previous_argument:
				commands.append("%s %s %s %s"%[number(time),target,str(mapping[key]),argument])
				previous_argument=argument
	if commands.is_empty():return filter
	return "asendcmd=c='%s',%s"%[";".join(commands),target+filter.substr(first_filter.length())]
