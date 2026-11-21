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
	return _native().call("presets")

static func _parameter(id: String, label: String, value: float, low: float, high: float) -> Dictionary:
	return _native().call("parameter", id, label, value, low, high)

static func preset(id: String) -> Dictionary:
	return _native().call("preset", id)

static func default_settings(id: String) -> Dictionary:
	return _native().call("default_settings", id)

static func finite(value: Variant, fallback: float) -> float:
	return _native().call("finite", value, fallback)

static func generate(id: String, settings: Dictionary, seed_value: int = 1, rate: int = 44100, job: RefCounted = null) -> AudioStreamWAV:
	return _native().call("generate", id, settings, seed_value, rate, job)

static func wave(phase: float, step: float, shape: String, pulse_width: float = 0.5) -> float:
	return _native().call("wave", phase, step, shape, pulse_width)

static func _blep(t: float, step: float) -> float:
	return _native().call("blep", t, step)

static func modulation(modulators: Array, target: String, t: float, duration: float, seed_value: int = 1) -> float:
	return _native().call("modulation", modulators, target, t, duration, seed_value)

static func pcm(samples: PackedFloat32Array, rate: int, stereo: bool = false) -> AudioStreamWAV:
	return _native().call("pcm", samples, rate, stereo)

static func layer(layers: Array, rate: int = 44100) -> AudioStreamWAV:
	return _native().call("layer", layers, rate)

static func variations(id: String, settings: Dictionary, seed_value: int, count: int = 4, rate: int = 44100) -> Array[AudioStreamWAV]:
	return _native().call("variations", id, settings, seed_value, count, rate)

static func save_preset(path: String, data: Dictionary) -> Error:
	return _native().call("save_preset", path, data)

static func load_preset(path: String) -> Dictionary:
	return _native().call("load_preset", path)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_synthesis")
