class_name KiwiAudioSynthesis
extends RefCounted
## Offline procedural synthesis. Call on a worker, then publish the completed WAV.
## Returned buffers are never retained or mutated by this class. These are stylized
## synthesized effects; imported recordings can be mixed in for acoustic realism.

const MAX_SECONDS := 60.0
const MAX_LAYERS := 32
const CATALOG := [
	["punch", "Punch", "Impacts", "thump", 0.35, 96.0, 0.45, 0.45, "Pitched body transient and short filtered air burst."],
	["metal_impact", "Metal impact", "Impacts", "metal", 1.5, 330.0, 0.65, 0.5, "Inharmonic resonator bank with a sharp excitation."],
	["wood_impact", "Wood impact", "Impacts", "wood", 0.5, 190.0, 0.45, 0.5, "Damped wooden modal resonances and a knock."],
	["glass_impact", "Glass impact", "Impacts", "glass", 1.8, 780.0, 0.7, 0.5, "Bright, unevenly spaced ringing modes."],
	["explosion", "Explosion", "Impacts", "explosion", 2.5, 48.0, 0.55, 0.65, "Low impact, changing-bandwidth blast and scattered debris."],
	["distant_explosion", "Distant explosion", "Impacts", "explosion", 4.0, 32.0, 0.15, 0.4, "Soft low-frequency blast with a long rumbling body."],
	["whoosh", "Whoosh", "Movement", "whoosh", 0.7, 650.0, 0.65, 0.5, "Moving band-pass air and a weak tonal trajectory."],
	["footsteps", "Footstep-like impacts", "Movement", "steps", 2.0, 100.0, 0.35, 0.55, "Alternating foot impacts with a textured sole contact."],
	["rolling", "Rolling object", "Movement", "roll", 2.0, 120.0, 0.45, 0.55, "Accelerating uneven contacts with a resonating body."],
	["jump", "Jump", "Movement", "jump", 0.45, 210.0, 0.5, 0.5, "Upward pitch envelope and a springy harmonic body."],
	["wood_creak", "Wood creak", "Materials and Foley", "creak", 1.4, 130.0, 0.4, 0.55, "Irregular stick-slip excitation of wooden resonances."],
	["metal_scrape", "Metal scraping", "Materials and Foley", "scrape", 1.7, 470.0, 0.7, 0.6, "Rough excitation through metallic resonances."],
	["glass_break", "Glass breaking", "Materials and Foley", "shatter", 1.7, 1200.0, 0.8, 0.8, "Initial crack followed by randomized ringing fragments."],
	["fabric_rustle", "Fabric rustle", "Materials and Foley", "rustle", 1.4, 800.0, 0.35, 0.55, "Clustered soft grains with changing friction."],
	["paper_crumple", "Paper crumple", "Materials and Foley", "crackle", 1.1, 1500.0, 0.8, 0.8, "Dense short buckling transients over a papery body."],
	["wind", "Wind", "Nature", "wind", 5.0, 240.0, 0.4, 0.45, "Slowly changing filtered gusts and tonal whistling."],
	["rain", "Rain", "Nature", "rain", 5.0, 1200.0, 0.6, 0.7, "Distributed droplet resonances over a fine diffuse bed."],
	["thunder", "Thunder", "Nature", "thunder", 5.0, 32.0, 0.4, 0.7, "Crack, multiple delayed low bodies and rolling rumble."],
	["water", "Flowing water", "Nature", "water", 5.0, 550.0, 0.5, 0.65, "Bubbling, pitch-falling grains and a running-water bed."],
	["fire", "Crackling fire", "Nature", "fire", 5.0, 280.0, 0.5, 0.65, "Low flame movement and sparse bright crackles."],
	["insects", "Insect ambience", "Nature", "insects", 5.0, 3200.0, 0.4, 0.6, "Several amplitude-modulated chirping voices."],
	["laser", "Laser", "Science Fiction", "laser", 0.65, 1500.0, 0.65, 0.5, "Band-limited harmonic oscillator with a falling pitch sweep."],
	["plasma", "Plasma shot", "Science Fiction", "plasma", 0.9, 210.0, 0.7, 0.6, "FM core, ring modulation and an electric transient."],
	["charge", "Charging weapon", "Science Fiction", "charge", 2.5, 140.0, 0.55, 0.6, "Accelerating FM pulses with a rising energy envelope."],
	["force_field", "Force field", "Science Fiction", "field", 4.0, 150.0, 0.6, 0.5, "Detuned additive voices with ring-modulated movement."],
	["sparkle", "Magic sparkle", "Magic and Fantasy", "sparkle", 2.0, 880.0, 0.65, 0.6, "Seeded pentatonic bell grains with individual decay."],
	["spell", "Spell cast", "Magic and Fantasy", "spell", 1.8, 440.0, 0.6, 0.65, "Rising resonant sweep resolving into harmonic chimes."],
	["enchantment", "Enchantment", "Magic and Fantasy", "enchant", 3.0, 330.0, 0.5, 0.5, "Slow harmonic shimmer with soft struck overtones."],
	["whisper", "Supernatural whisper-like", "Magic and Fantasy", "whisper", 3.0, 400.0, 0.5, 0.55, "Moving formant-shaped air; does not synthesize speech."],
	["drone", "Low horror drone", "Horror", "drone", 6.0, 49.0, 0.5, 0.55, "Slow detuned low partials and a beating dissonant overtone."],
	["sting", "Dissonant sting", "Horror", "sting", 1.8, 220.0, 0.75, 0.6, "A sharply struck close-interval cluster."],
	["heartbeat", "Heartbeat", "Horror", "heartbeat", 4.0, 56.0, 0.3, 0.5, "Paired differently voiced body pulses."],
	["reverse_swell", "Reverse swell", "Horror", "reverse", 3.0, 150.0, 0.55, 0.5, "Reverse-shaped modal energy with a controlled final fade."],
	["boing", "Cartoon boing", "Cartoon and Comedy", "boing", 1.2, 180.0, 0.65, 0.6, "Damped elastic pitch oscillation and spring harmonics."],
	["pop", "Pop", "Cartoon and Comedy", "pop", 0.16, 440.0, 0.4, 0.5, "Fast descending hollow resonance."],
	["slide_whistle", "Slide whistle", "Cartoon and Comedy", "whistle", 1.2, 650.0, 0.55, 0.5, "Smooth curved pitch glide with gentle breath."],
	["rubber", "Rubber stretch", "Cartoon and Comedy", "rubber", 1.3, 125.0, 0.6, 0.55, "Nonlinear pitch stretch and resonant harmonic squeak."],
	["ui_click", "Click", "User Interface", "click", 0.09, 1100.0, 0.5, 0.4, "Tiny damped dual-resonance click."],
	["ui_confirm", "Confirm", "User Interface", "confirm", 0.45, 660.0, 0.5, 0.4, "Two clear upward harmonic tones."],
	["ui_cancel", "Cancel", "User Interface", "cancel", 0.45, 520.0, 0.4, 0.4, "Two descending muted tones."],
	["ui_notify", "Notification", "User Interface", "notify", 0.9, 780.0, 0.5, 0.4, "Three short rounded bell notes."],
	["riser", "Riser", "Music and Cinematic Transitions", "riser", 4.0, 110.0, 0.65, 0.65, "Rising harmonic stack, opening filter and accelerating pulses."],
	["sub_drop", "Sub drop", "Music and Cinematic Transitions", "subdrop", 2.5, 130.0, 0.3, 0.6, "Exponential low-frequency pitch drop with a smooth tail."],
	["reverse_cymbal", "Reverse cymbal", "Music and Cinematic Transitions", "cymbal", 3.0, 700.0, 0.7, 0.55, "Rising inharmonic resonances and high-frequency diffusion."],
	["logo_sting", "Logo sting", "Music and Cinematic Transitions", "logo", 2.6, 330.0, 0.6, 0.55, "Timed consonant bell voicing with a soft low foundation."],
	["motor", "Motor", "Mechanical", "motor", 3.0, 70.0, 0.55, 0.6, "Periodic engine harmonics with speed flutter and air."],
	["servo", "Servo", "Mechanical", "servo", 1.5, 420.0, 0.65, 0.5, "Stepped motor speed, harmonic whine and movement envelope."],
	["gear", "Gear movement", "Mechanical", "gear", 2.0, 210.0, 0.6, 0.55, "Repeated toothed contacts exciting metallic modes."],
	["hydraulic", "Hydraulic movement", "Mechanical", "hydraulic", 2.0, 200.0, 0.4, 0.65, "Pressurized filtered air and a changing pump fundamental."],
	["sample_grains", "Sample granulator", "Samples", "sample", 3.0, 440.0, 0.5, 0.5, "Overlapping Hann-windowed grains from a supplied PCM sample."]
]

static func presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Array in CATALOG:
		var names: Array = ["Pitch", "Brightness", "Density"]
		if row[3] in ["metal", "wood", "glass", "thump", "pop", "subdrop", "sting", "click"]: names[2] = "Decay"
		elif row[3] in ["confirm", "cancel", "notify", "logo"]: names[2] = "Spacing"
		if row[3] in ["explosion", "thunder"]: names = ["Body pitch", "Sharpness", "Debris / crack"]
		elif row[3] == "boing": names = ["Pitch", "Elasticity", "Bounce"]
		elif row[3] in ["laser", "plasma"]: names = ["Pitch", "Sweep", "Energy"]
		result.append({"id": row[0], "label": row[1], "category": row[2], "description": row[8],
			"parameters": [
				_parameter("duration", "Duration (seconds)", float(row[4]), 0.03, MAX_SECONDS),
				_parameter("pitch", names[0], float(row[5]), 20.0, 8000.0),
				_parameter("character", names[1], float(row[6]), 0.0, 1.0),
				_parameter("density", names[2], float(row[7]), 0.0, 1.0),
				_parameter("power", "Power", 0.75, 0.0, 1.0),
				_parameter("distance", "Distance", 0.0, 0.0, 1.0)]})
	return result

static func _parameter(id: String, label: String, value: float, low: float, high: float) -> Dictionary:
	return {"id": id, "label": label, "default": value, "min": low, "max": high}

static func preset(id: String) -> Dictionary:
	for entry: Dictionary in presets():
		if entry.id == id: return entry
	return {}

static func default_settings(id: String) -> Dictionary:
	var result: Dictionary = {}
	for parameter: Dictionary in preset(id).get("parameters", []):
		result[parameter.id] = parameter.default
	return result

static func finite(value: Variant, fallback: float) -> float:
	var number := float(value) if value is int or value is float else fallback
	return number if is_finite(number) else fallback

static func generate(id: String, settings: Dictionary, seed_value: int = 1, rate: int = 44100, job: RefCounted = null) -> AudioStreamWAV:
	var row: Array = []
	for candidate: Array in CATALOG:
		if candidate[0] == id:
			row = candidate
			break
	if row.is_empty(): return null
	var sample_rate := clampi(rate, 8000, 192000)
	var duration := clampf(finite(settings.get("duration", row[4]), float(row[4])), 0.03, MAX_SECONDS)
	var count := maxi(2, int(round(duration * sample_rate)))
	var pitch := clampf(finite(settings.get("pitch", row[5]), float(row[5])), 20.0, minf(8000.0, sample_rate * 0.22))
	var color := clampf(finite(settings.get("character", row[6]), float(row[6])), 0.0, 1.0)
	var density := clampf(finite(settings.get("density", row[7]), float(row[7])), 0.0, 1.0)
	var power := clampf(finite(settings.get("power", 0.75), 0.75), 0.0, 1.0)
	var distance := clampf(finite(settings.get("distance", 0.0), 0.0), 0.0, 1.0)
	var kind := str(row[3])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	pitch *= rng.randf_range(0.985, 1.015)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	var phase2 := 0.0
	var low := 0.0
	var slow := 0.0
	var band := 0.0
	var previous := 0.0
	var distance_low := 0.0
	var timbre_low := 0.0
	var grain_envelope := 0.0
	var grain_pitch := pitch
	var grain_phase := 0.0
	var grain_decay := exp(-1.0 / (sample_rate * 0.035))
	var mods: Array = settings.get("modulators", [])
	var pan_modulated:=mods.any(func(item:Dictionary):return str(item.get("target",""))=="pan" and bool(item.get("enabled",true)))
	var sample_data := PackedVector2Array()
	if kind == "sample":
		var sample_stream := ActorAudio.source(settings.get("sample", ""))
		if sample_stream == null: return null
		var decoded := KiwiAudioSourceCache.decode(sample_stream, sample_rate, 0.0, minf(MAX_SECONDS, sample_stream.get_length()), MAX_SECONDS)
		if not str(decoded.get("error", "")).is_empty(): return null
		sample_data = decoded.samples
		if sample_data.size() < 2: return null
	var sample_frames := sample_data.size()
	var grains: Array = []
	var next_grain := 0
	var grain_size := maxi(16, int(sample_rate * (0.025 + 0.12 * color)))
	for i in count:
		if job != null and i % 8192 == 0:
			if job.is_cancelled(): return null
			job.update(float(i)/count,"Synthesizing sound")
		var t := float(i) / sample_rate
		var u := float(i) / float(count - 1)
		var n := rng.randf_range(-1.0, 1.0)
		var cutoff := 160.0 + color * color * 10000.0
		cutoff *= pow(2.0, modulation(mods, "cutoff", t, duration, seed_value))
		var alpha := 1.0 - exp(-TAU * minf(cutoff, sample_rate * 0.42) / sample_rate)
		low += alpha * (n - low)
		slow += (1.0 - exp(-TAU * 85.0 / sample_rate)) * (n - slow)
		band += (1.0 - exp(-TAU * 1500.0 / sample_rate)) * ((n - low) - band)
		var frequency := pitch * pow(2.0, modulation(mods, "pitch", t, duration, seed_value) / 12.0)
		match kind:
			"thump", "pop": frequency *= 1.0 + (2.8 if kind == "pop" else 1.8) * exp(-t * 40.0)
			"laser": frequency *= pow(0.06 + 0.4 * (1.0 - color), u)
			"plasma": frequency *= 0.35 + 1.9 * exp(-u * 6.0)
			"charge", "riser": frequency *= pow(2.0, u * (2.0 + color * 3.0))
			"subdrop": frequency = maxf(22.0, frequency * exp(-u * (2.0 + color)))
			"boing": frequency *= 1.0 + (0.08 + color * 0.4) * sin(t * TAU * (4.0 + 9.0 * density)) * exp(-u * 2.0)
			"jump": frequency *= pow(2.0, u * (1.0 + density * 1.2))
			"whistle": frequency *= pow(2.0, (u * u - 0.5) * (1.0 + color * 2.0))
			"rubber": frequency *= 0.6 + u * u * 3.0 + 0.18 * sin(t * (25.0 + density * 60.0))
			"servo": frequency *= 0.7 + floor(u * (3.0 + density * 4.0)) * 0.18 + 0.012 * sin(t * 130.0)
			"motor": frequency *= 0.65 + 0.35 * sin(u * PI * 0.5) + (0.003 + density * 0.02) * sin(t * 37.0)
			"water": frequency *= 0.7 + 0.5 * sin(t * 5.3)
		frequency = clampf(frequency, 12.0, sample_rate * 0.24)
		phase = fposmod(phase + frequency / sample_rate, 1.0)
		phase2 = fposmod(phase2 + frequency * 1.007 / sample_rate, 1.0)
		var tone := sin(TAU * phase)
		var value := 0.0
		match kind:
			"thump", "pop":
				value = tone * exp(-u * (7.0 if kind == "thump" else 10.0) * (1.6 - density)) + low * (0.35 if kind == "thump" else 0.08) * exp(-u * 28.0)
			"metal", "glass", "wood":
				var ratios: Array = [1.0, 2.756, 5.404, 8.933] if kind == "metal" else ([1.0, 2.32, 4.25, 6.63] if kind == "glass" else [1.0, 1.47, 2.09, 3.12])
				for k in ratios.size():
					var modal_frequency := frequency * float(ratios[k])
					if modal_frequency < sample_rate * 0.44:
						value += sin(TAU * modal_frequency * t) * exp(-u * (2.2 + k * (0.7 if kind != "wood" else 2.8)) * (1.6 - density)) / (1.0 + k)
				value = value * 0.48 + n * 0.18 * exp(-t * 180.0)
			"explosion", "thunder":
				value = slow * 4.0 * exp(-u * 3.5) + low * 0.75 * exp(-u * 7.0) + sin(TAU * pitch * t * (1.0 + exp(-t * 10.0))) * exp(-t * 5.0) * 0.45
				if kind == "thunder":
					for delay in [0.13, 0.37, 0.81]:
						var age := t - float(delay)
						if age >= 0.0: value += slow * 1.7 * exp(-age * 1.5) * (1.0 - exp(-age * 30.0))
				value += n * density * maxf(0.0, sin(t * 91.0 + sin(t * 8.0))) * exp(-u * 7.0) * 0.22
			"whoosh":
				var sweep_alpha := 1.0 - exp(-TAU * (200.0 + sin(u * PI) * pitch * 6.0) / sample_rate)
				previous += sweep_alpha * (n - previous)
				value = ((n - previous) * 0.35 + previous * 0.7 + tone * 0.07) * pow(sin(u * PI), 1.5 + density * 3.0)
			"steps":
				var step_age := fposmod(t, 0.65 - density * 0.35)
				value = (sin(TAU * pitch * step_age) * 0.65 + low * 0.8) * exp(-step_age * 30.0) * minf(step_age * 900.0, 1.0)
			"roll", "gear":
				var speed := 5.0 + density * 24.0
				var contact := pow(maxf(0.0, sin(t * TAU * speed + (2.0 * u * u if kind == "roll" else 0.0))), 16.0)
				value = (tone * 0.55 + sin(TAU * phase * 3.0) * 0.15 + low * 0.5) * contact
			"jump": value = wave(phase, frequency / sample_rate, "triangle") * exp(-u * 4.0) * 0.85
			"creak":
				var friction := pow(maxf(0.0, sin(t * (18.0 + density * 40.0 + 9.0 * sin(t * 4.2)))), 3.0)
				value = (tone + 0.4 * sin(t * TAU * pitch * 2.37)) * friction * 0.48 * sin(u * PI)
			"scrape":
				value = (band * sin(t * TAU * pitch) + low * sin(t * TAU * pitch * 2.72)) * (0.55 + 0.45 * sin(t * (15.0 + density * 40.0))) * sin(u * PI)
			"shatter", "sparkle", "rain", "water", "crackle", "fire", "rustle":
				var hits := 6.0 + density * density * (450.0 if kind in ["rain", "crackle", "rustle"] else 42.0)
				if rng.randf() < hits / sample_rate:
					grain_envelope = rng.randf_range(0.3, 1.0)
					grain_pitch = pitch * rng.randf_range(0.6, 3.0)
					if kind == "sparkle":
						var semitone: int = [0, 2, 4, 7, 9, 12, 14, 16][rng.randi_range(0, 7)]
						grain_pitch = pitch * pow(2.0, semitone / 12.0)
					grain_phase = 0.0
				grain_pitch = minf(grain_pitch, sample_rate * 0.4)
				grain_phase = fposmod(grain_phase + grain_pitch / sample_rate, 1.0)
				grain_envelope *= grain_decay if kind != "sparkle" else exp(-1.0 / (sample_rate * 0.16))
				var grain := sin(TAU * grain_phase + (4.0 * grain_envelope if kind == "water" else 0.0)) * grain_envelope
				value = grain * 0.65
				if kind == "rain": value += (n - low) * 0.16 + low * 0.1
				elif kind == "water": value += low * 0.4
				elif kind == "fire": value = grain * n * 0.6 + slow * 1.7
				elif kind in ["crackle", "rustle"]: value = grain_envelope * (band * 0.8 + sin(TAU * grain_phase) * band * 0.2) * (1.3 if kind == "crackle" else 0.65)
				elif kind == "shatter": value = value * exp(-u * 2.0) + n * exp(-t * 140.0) * 0.35
			"wind":
				value = low * (0.3 + 0.7 * pow(0.5 + 0.5 * sin(t * (0.5 + density * 2.5) + sin(t * 0.71)), 2.0)) + tone * 0.07 * (0.5 + 0.5 * sin(t * 2.0))
			"insects":
				for k in 3:
					var chirp := pow(maxf(0.0, sin(t * (3.0 + density * 6.0 + k * 1.31))), 8.0)
					value += sin(t * TAU * pitch * (1.0 + k * 0.17)) * chirp * (0.22 / (k + 1))
			"laser":
				value = (wave(phase, frequency / sample_rate, "saw") * (0.15 + density * 0.7) + tone * (0.85 - density * 0.7)) * exp(-u * 5.0)
			"plasma":
				value = sin(TAU * phase + (1.0 + color * 5.0) * sin(TAU * phase * 2.0) * exp(-u * 3.0)) * exp(-u * 5.0) * (0.65 + 0.35 * sin(t * (80.0 + density * 190.0)))
			"charge", "riser":
				value = (wave(phase, frequency / sample_rate, "saw") * 0.3 + sin(TAU * phase + sin(TAU * phase2) * color * 2.0) * 0.45 + low * u * 0.25) * pow(u, 0.6) * (0.7 + 0.3 * sin(t * (5.0 + density * 12.0 + 30.0 * u)))
			"field":
				value = (tone * 0.45 + sin(TAU * phase2) * 0.35 + sin(t * TAU * pitch * 1.5) * 0.2) * (0.65 + 0.35 * sin(t * TAU * (1.0 + density * 9.0)))
			"spell":
				value = sin(TAU * phase + 2.0 * sin(t * TAU * pitch * (1.0 + u))) * pow(sin(u * PI), 2.0) * 0.4
				value += (sin(t * TAU * pitch * 1.5) + sin(t * TAU * pitch * 2.0)) * exp(-maxf(0.0, u - 0.55) * 6.0) * smoothstep(0.2 + density * 0.3, 0.4 + density * 0.3, u) * 0.2
			"enchant":
				value = (tone + 0.5 * sin(t * TAU * pitch * 1.5) + 0.3 * sin(t * TAU * pitch * 2.0)) * 0.35 * (0.6 + 0.4 * sin(t * (1.0 + density * 4.0))) * sin(u * PI)
			"whisper":
				value = low * (sin(t * TAU * pitch * 1.625) * 0.4 + sin(t * TAU * pitch * (2.75 + 0.75 * sin(t * 1.1))) * 0.4) * (0.4 + 0.6 * pow(sin(t * (2.0 + density * 5.0)), 2.0))
			"drone":
				value = (tone * 0.45 + sin(TAU * phase2) * 0.3 + sin(t * TAU * pitch * 2.07) * 0.18) * (0.75 + 0.25 * sin(t * (0.3 + density * 1.2)))
			"sting":
				for interval in [0.0, 1.0, 6.0, 13.0]:
					value += sin(t * TAU * pitch * pow(2.0, float(interval) / 12.0)) * 0.22 * exp(-u * 4.0 * (1.6 - density))
			"heartbeat":
				var age := fposmod(t, 1.0 - density * 0.45)
				value = sin(TAU * pitch * age) * exp(-age * 25.0) * smoothstep(0.0, 0.01, age)
				if age >= 0.18:
					value += sin(TAU * pitch * 1.35 * (age - 0.18)) * exp(-(age - 0.18) * 35.0) * smoothstep(0.18, 0.19, age) * 0.7
			"reverse": value = (tone * 0.45 + sin(t * TAU * pitch * 2.756) * 0.25 + low * 0.3) * pow(u, 1.5 + density * 3.0)
			"boing": value = (tone * 0.65 + sin(TAU * phase * 2.0) * 0.2 + sin(TAU * phase * 3.0) * 0.1) * exp(-u * 3.8)
			"whistle": value = (tone * 0.7 + low * (0.02 + density * 0.12)) * sin(u * PI)
			"rubber": value = sin(TAU * phase + color * sin(TAU * phase * 3.0)) * sin(u * PI) * 0.65
			"click": value = (tone * 0.6 + sin(t * TAU * pitch * 1.61) * 0.3) * exp(-u * 12.0 * (1.6 - density))
			"confirm", "cancel", "notify", "logo":
				var note_count := 4 if kind == "logo" else (3 if kind == "notify" else 2)
				var spacing := duration / (note_count + 2.0) * (0.6 + density * 0.8)
				var intervals: Array = [0, 7, 12, 16] if kind != "cancel" else [0, -5]
				for k in note_count:
					var age := t - spacing * k
					var hz := pitch * pow(2.0, float(intervals[k]) / 12.0)
					if age >= 0.0 and hz < sample_rate * 0.4:
						value += (sin(TAU * hz * age) + 0.2 * sin(TAU * hz * 2.01 * age)) * exp(-age * (7.0 if kind != "logo" else 2.5)) * smoothstep(0.0, 0.006, age) * 0.42
			"subdrop": value = tone * exp(-u * 2.8 * (1.6 - density)) * 0.85
			"cymbal":
				for ratio in [1.0, 1.43, 1.93, 2.71, 3.91]:
					if pitch * float(ratio) < sample_rate * 0.44:
						value += sin(t * TAU * pitch * float(ratio)) * 0.1
				value = (value + (n - low) * 0.4) * pow(u, 1.0 + density * 2.0)
			"motor": value = (wave(phase, frequency / sample_rate, "saw") * 0.45 + tone * 0.35 + sin(TAU * phase * 4.0) * 0.12 + low * 0.15) * sin(u * PI)
			"servo": value = (wave(phase, frequency / sample_rate, "pulse") * 0.5 + tone * 0.3) * pow(sin(u * PI), 0.6)
			"hydraulic": value = (low * (0.3 + density * 0.6) + tone * (0.3 - density * 0.2) + sin(TAU * phase * 3.0) * 0.08) * smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.7, 1.0, u))
			"sample":
				if sample_frames > 1:
					if i >= next_grain:
						grains.append({"start": i, "source": rng.randf() * maxf(0.0, sample_frames - grain_size - 1.0)})
						next_grain = i + maxi(1, int(grain_size * (0.65 - density * 0.5)))
					for g in range(grains.size() - 1, -1, -1):
						var age: int = i - int(grains[g].start)
						if age >= grain_size:
							grains.remove_at(g)
							continue
						var position := float(grains[g].source) + age * pitch / 440.0
						var index := int(position)
						if index + 1 < sample_frames:
							var a := (sample_data[index].x + sample_data[index].y) * 0.5
							var b := (sample_data[index + 1].x + sample_data[index + 1].y) * 0.5
							value += lerpf(a, b, position - index) * (0.5 - 0.5 * cos(TAU * age / grain_size)) * 0.45
		# Brightness is a genuine output low-pass control for every preset.
		timbre_low += alpha * (value - timbre_low)
		value = timbre_low
		var amp_mod := clampf(1.0 + modulation(mods, "amplitude", t, duration, seed_value), 0.0, 4.0)
		distance_low += (1.0 - exp(-TAU * lerpf(16000.0, 450.0, distance) / sample_rate)) * (value - distance_low)
		value = lerpf(value, distance_low, distance) * power * (1.0 - distance * 0.65) * amp_mod
		var boundary := smoothstep(0.0, minf(0.004, duration * 0.12), t) * smoothstep(0.0, minf(0.02, duration * 0.2), duration - t - 1.0 / sample_rate)
		samples[i] = value * boundary if is_finite(value) else 0.0
	if pan_modulated:
		var stereo:=PackedFloat32Array();stereo.resize(count*2)
		for i in count:
			if i%8192==0 and job!=null and job.is_cancelled():return null
			var pan:=clampf(modulation(mods,"pan",float(i)/sample_rate,duration,seed_value),-1,1)
			stereo[i*2]=samples[i]*minf(1.,1.-pan);stereo[i*2+1]=samples[i]*minf(1.,1.+pan)
		return pcm(stereo,sample_rate,true)
	return pcm(samples, sample_rate)

## PolyBLEP suppresses oscillator discontinuities; additive/FM patches restrict
## carrier/partial frequencies. Extreme FM settings can still introduce aliasing.
static func wave(phase: float, step: float, shape: String, pulse_width: float = 0.5) -> float:
	var p := fposmod(phase, 1.0)
	match shape:
		"saw": return 2.0 * p - 1.0 - _blep(p, step)
		"pulse", "square": return (1.0 if p < pulse_width else -1.0) + _blep(p, step) - _blep(fposmod(p - pulse_width, 1.0), step)
		"triangle": return 1.0 - 4.0 * absf(p - 0.5)
	return sin(TAU * p)

static func _blep(t: float, step: float) -> float:
	var dt := clampf(step, 0.000001, 0.49)
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0

static func modulation(modulators: Array, target: String, t: float, duration: float, seed_value: int = 1) -> float:
	var result := 0.0
	for entry: Variant in modulators:
		if not entry is Dictionary or not bool(entry.get("enabled",true)) or str(entry.get("target", "")) != target: continue
		var speed := clampf(finite(entry.get("rate", 1.0), 1.0), 0.0, 100.0)
		var value := 0.0
		match str(entry.get("kind", "lfo")):
			"lfo": value = sin(TAU * speed * t + finite(entry.get("phase", 0.0), 0.0))
			"envelope": value = pow(clampf(t / maxf(duration, 0.001), 0.0, 1.0), maxf(0.1, finite(entry.get("curve", 1.0), 1.0)))
			"random":
				var index := int(floor(t * speed))
				value = sin(float(index * 7919 + seed_value * 104729) * 0.0131) * 0.5 + sin(float(index * 3571 + seed_value) * 0.071) * 0.5
			"step":
				var values: Array = entry.get("values", [0.0])
				if not values.is_empty(): value = finite(values[posmod(int(floor(t * speed)), values.size())], 0.0)
			"velocity": value = clampf(finite(entry.get("velocity", 1.0), 1.0), 0.0, 1.0)
			"automation":
				var points: Array = entry.get("points", [])
				for j in points.size():
					var point: Dictionary = points[j]
					if t >= finite(point.get("time", 0.0), 0.0): value = finite(point.get("value", 0.0), 0.0)
					if j + 1 < points.size():
						var next: Dictionary = points[j + 1]
						var a := finite(point.get("time", 0.0), 0.0)
						var b := finite(next.get("time", 0.0), 0.0)
						if t >= a and t < b:
							value = lerpf(finite(point.get("value", 0.0), 0.0), finite(next.get("value", 0.0), 0.0), (t - a) / maxf(0.000001, b - a))
							break
		result += value * finite(entry.get("amount", 1.0), 1.0)
	return result

static func pcm(samples: PackedFloat32Array, rate: int, stereo: bool = false) -> AudioStreamWAV:
	var maximum := 0.0
	for value in samples:
		if is_finite(value): maximum = maxf(maximum, absf(value))
	var gain := 0.96 / maximum if maximum > 0.96 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := samples[i] if is_finite(samples[i]) else 0.0
		bytes.encode_s16(i * 2, int(round(clampf(value * gain, -0.96, 0.96) * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = clampi(rate, 8000, 192000)
	stream.stereo = stereo
	stream.data = bytes
	return stream

## Layers may hold a generated stream or a generator ID/settings. This is an
## offline convenience; the workspace maps these same layer fields to clips.
static func layer(layers: Array, rate: int = 44100) -> AudioStreamWAV:
	var rendered: Array[Dictionary] = []
	var length_frames := 1
	var sample_rate := clampi(rate, 8000, 192000)
	for item: Variant in layers.slice(0, MAX_LAYERS):
		if not item is Dictionary or bool(item.get("mute", false)): continue
		var stream := item.get("stream") as AudioStreamWAV
		if stream == null and item.has("generator"):
			stream = generate(str(item.generator), item.get("settings", {}), int(item.get("seed", 1)), sample_rate)
		if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS: continue
		var start := maxi(0, int(finite(item.get("start", 0.0), 0.0) * sample_rate))
		var speed := pow(2.0, clampf(finite(item.get("pitch", 0.0), 0.0), -48.0, 48.0) / 12.0)
		var frames := int(stream.get_length() * sample_rate / speed)
		frames = mini(frames, int(clampf(finite(item.get("duration", MAX_SECONDS), MAX_SECONDS), 0.0, MAX_SECONDS) * sample_rate))
		length_frames = mini(sample_rate * int(MAX_SECONDS), maxi(length_frames, start + frames))
		rendered.append({"stream": stream, "data": stream.data, "start": start, "frames": frames, "speed": speed, "volume": clampf(finite(item.get("volume", 1.0), 1.0), 0.0, 8.0), "pan": clampf(finite(item.get("pan", 0.0), 0.0), -1.0, 1.0)})
	var mix := PackedFloat32Array()
	mix.resize(length_frames * 2)
	for item: Dictionary in rendered:
		var stream: AudioStreamWAV = item.stream
		var data: PackedByteArray = item.data
		var channels := 2 if stream.stereo else 1
		var source_frames := data.size() / (channels * 2)
		var pan := float(item.pan)
		var gains := Vector2(sqrt((1.0 - pan) * 0.5), sqrt((1.0 + pan) * 0.5))
		for j in mini(int(item.frames), length_frames - int(item.start)):
			var source_position := j * float(stream.mix_rate) / sample_rate * float(item.speed)
			var index := int(source_position)
			if index >= source_frames: break
			var blend := source_position - index
			var end_index := mini(index + 1, source_frames - 1)
			var fade := minf(1.0, j / maxf(1.0, sample_rate * 0.003)) * minf(1.0, (int(item.frames) - 1 - j) / maxf(1.0, sample_rate * 0.006))
			for ch in 2:
				var source_channel := mini(ch, channels - 1)
				var a := data.decode_s16((index * channels + source_channel) * 2) / 32768.0
				var b := data.decode_s16((end_index * channels + source_channel) * 2) / 32768.0
				mix[(int(item.start) + j) * 2 + ch] += lerpf(a, b, blend) * float(item.volume) * gains[ch] * fade
	return pcm(mix, sample_rate, true)

static func variations(id: String, settings: Dictionary, seed_value: int, count: int = 4, rate: int = 44100) -> Array[AudioStreamWAV]:
	var result: Array[AudioStreamWAV] = []
	for index in clampi(count, 1, 16):
		result.append(generate(id, settings, seed_value + index, rate))
	return result

static func save_preset(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": "kiwi.audio.preset", "version": 1, "data": data}, "\t"))
	file.close()
	return OK

static func load_preset(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("format") != "kiwi.audio.preset" or int(parsed.get("version", 0)) != 1: return {}
	var data: Variant = parsed.get("data", {})
	return data if data is Dictionary else {}

