using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioSynthesisOperations : RefCounted
{
    private const string CatalogJson = @"[[""punch"",""Punch"",""Impacts"",""thump"",0.35,96.0,0.45,0.45,""Pitched body transient and short filtered air burst.""],[""metal_impact"",""Metal impact"",""Impacts"",""metal"",1.5,330.0,0.65,0.5,""Inharmonic resonator bank with a sharp excitation.""],[""wood_impact"",""Wood impact"",""Impacts"",""wood"",0.5,190.0,0.45,0.5,""Damped wooden modal resonances and a knock.""],[""glass_impact"",""Glass impact"",""Impacts"",""glass"",1.8,780.0,0.7,0.5,""Bright, unevenly spaced ringing modes.""],[""explosion"",""Explosion"",""Impacts"",""explosion"",2.5,48.0,0.55,0.65,""Low impact, changing-bandwidth blast and scattered debris.""],[""distant_explosion"",""Distant explosion"",""Impacts"",""explosion"",4.0,32.0,0.15,0.4,""Soft low-frequency blast with a long rumbling body.""],[""whoosh"",""Whoosh"",""Movement"",""whoosh"",0.7,650.0,0.65,0.5,""Moving band-pass air and a weak tonal trajectory.""],[""footsteps"",""Footstep-like impacts"",""Movement"",""steps"",2.0,100.0,0.35,0.55,""Alternating foot impacts with a textured sole contact.""],[""rolling"",""Rolling object"",""Movement"",""roll"",2.0,120.0,0.45,0.55,""Accelerating uneven contacts with a resonating body.""],[""jump"",""Jump"",""Movement"",""jump"",0.45,210.0,0.5,0.5,""Upward pitch envelope and a springy harmonic body.""],[""wood_creak"",""Wood creak"",""Materials and Foley"",""creak"",1.4,130.0,0.4,0.55,""Irregular stick-slip excitation of wooden resonances.""],[""metal_scrape"",""Metal scraping"",""Materials and Foley"",""scrape"",1.7,470.0,0.7,0.6,""Rough excitation through metallic resonances.""],[""glass_break"",""Glass breaking"",""Materials and Foley"",""shatter"",1.7,1200.0,0.8,0.8,""Initial crack followed by randomized ringing fragments.""],[""fabric_rustle"",""Fabric rustle"",""Materials and Foley"",""rustle"",1.4,800.0,0.35,0.55,""Clustered soft grains with changing friction.""],[""paper_crumple"",""Paper crumple"",""Materials and Foley"",""crackle"",1.1,1500.0,0.8,0.8,""Dense short buckling transients over a papery body.""],[""wind"",""Wind"",""Nature"",""wind"",5.0,240.0,0.4,0.45,""Slowly changing filtered gusts and tonal whistling.""],[""rain"",""Rain"",""Nature"",""rain"",5.0,1200.0,0.6,0.7,""Distributed droplet resonances over a fine diffuse bed.""],[""thunder"",""Thunder"",""Nature"",""thunder"",5.0,32.0,0.4,0.7,""Crack, multiple delayed low bodies and rolling rumble.""],[""water"",""Flowing water"",""Nature"",""water"",5.0,550.0,0.5,0.65,""Bubbling, pitch-falling grains and a running-water bed.""],[""fire"",""Crackling fire"",""Nature"",""fire"",5.0,280.0,0.5,0.65,""Low flame movement and sparse bright crackles.""],[""insects"",""Insect ambience"",""Nature"",""insects"",5.0,3200.0,0.4,0.6,""Several amplitude-modulated chirping voices.""],[""laser"",""Laser"",""Science Fiction"",""laser"",0.65,1500.0,0.65,0.5,""Band-limited harmonic oscillator with a falling pitch sweep.""],[""plasma"",""Plasma shot"",""Science Fiction"",""plasma"",0.9,210.0,0.7,0.6,""FM core, ring modulation and an electric transient.""],[""charge"",""Charging weapon"",""Science Fiction"",""charge"",2.5,140.0,0.55,0.6,""Accelerating FM pulses with a rising energy envelope.""],[""force_field"",""Force field"",""Science Fiction"",""field"",4.0,150.0,0.6,0.5,""Detuned additive voices with ring-modulated movement.""],[""sparkle"",""Magic sparkle"",""Magic and Fantasy"",""sparkle"",2.0,880.0,0.65,0.6,""Seeded pentatonic bell grains with individual decay.""],[""spell"",""Spell cast"",""Magic and Fantasy"",""spell"",1.8,440.0,0.6,0.65,""Rising resonant sweep resolving into harmonic chimes.""],[""enchantment"",""Enchantment"",""Magic and Fantasy"",""enchant"",3.0,330.0,0.5,0.5,""Slow harmonic shimmer with soft struck overtones.""],[""whisper"",""Supernatural whisper-like"",""Magic and Fantasy"",""whisper"",3.0,400.0,0.5,0.55,""Moving formant-shaped air; does not synthesize speech.""],[""drone"",""Low horror drone"",""Horror"",""drone"",6.0,49.0,0.5,0.55,""Slow detuned low partials and a beating dissonant overtone.""],[""sting"",""Dissonant sting"",""Horror"",""sting"",1.8,220.0,0.75,0.6,""A sharply struck close-interval cluster.""],[""heartbeat"",""Heartbeat"",""Horror"",""heartbeat"",4.0,56.0,0.3,0.5,""Paired differently voiced body pulses.""],[""reverse_swell"",""Reverse swell"",""Horror"",""reverse"",3.0,150.0,0.55,0.5,""Reverse-shaped modal energy with a controlled final fade.""],[""boing"",""Cartoon boing"",""Cartoon and Comedy"",""boing"",1.2,180.0,0.65,0.6,""Damped elastic pitch oscillation and spring harmonics.""],[""pop"",""Pop"",""Cartoon and Comedy"",""pop"",0.16,440.0,0.4,0.5,""Fast descending hollow resonance.""],[""slide_whistle"",""Slide whistle"",""Cartoon and Comedy"",""whistle"",1.2,650.0,0.55,0.5,""Smooth curved pitch glide with gentle breath.""],[""rubber"",""Rubber stretch"",""Cartoon and Comedy"",""rubber"",1.3,125.0,0.6,0.55,""Nonlinear pitch stretch and resonant harmonic squeak.""],[""ui_click"",""Click"",""User Interface"",""click"",0.09,1100.0,0.5,0.4,""Tiny damped dual-resonance click.""],[""ui_confirm"",""Confirm"",""User Interface"",""confirm"",0.45,660.0,0.5,0.4,""Two clear upward harmonic tones.""],[""ui_cancel"",""Cancel"",""User Interface"",""cancel"",0.45,520.0,0.4,0.4,""Two descending muted tones.""],[""ui_notify"",""Notification"",""User Interface"",""notify"",0.9,780.0,0.5,0.4,""Three short rounded bell notes.""],[""riser"",""Riser"",""Music and Cinematic Transitions"",""riser"",4.0,110.0,0.65,0.65,""Rising harmonic stack, opening filter and accelerating pulses.""],[""sub_drop"",""Sub drop"",""Music and Cinematic Transitions"",""subdrop"",2.5,130.0,0.3,0.6,""Exponential low-frequency pitch drop with a smooth tail.""],[""reverse_cymbal"",""Reverse cymbal"",""Music and Cinematic Transitions"",""cymbal"",3.0,700.0,0.7,0.55,""Rising inharmonic resonances and high-frequency diffusion.""],[""logo_sting"",""Logo sting"",""Music and Cinematic Transitions"",""logo"",2.6,330.0,0.6,0.55,""Timed consonant bell voicing with a soft low foundation.""],[""motor"",""Motor"",""Mechanical"",""motor"",3.0,70.0,0.55,0.6,""Periodic engine harmonics with speed flutter and air.""],[""servo"",""Servo"",""Mechanical"",""servo"",1.5,420.0,0.65,0.5,""Stepped motor speed, harmonic whine and movement envelope.""],[""gear"",""Gear movement"",""Mechanical"",""gear"",2.0,210.0,0.6,0.55,""Repeated toothed contacts exciting metallic modes.""],[""hydraulic"",""Hydraulic movement"",""Mechanical"",""hydraulic"",2.0,200.0,0.4,0.65,""Pressurized filtered air and a changing pump fundamental.""],[""sample_grains"",""Sample granulator"",""Samples"",""sample"",3.0,440.0,0.5,0.5,""Overlapping Hann-windowed grains from a supplied PCM sample.""]]";
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var found) ? found : fallback;
    public double finite(Variant value, double fallback) { double number = value.VariantType is Variant.Type.Int or Variant.Type.Float ? value.AsDouble() : fallback; return double.IsFinite(number) ? number : fallback; }
    public double wave(double phase, double step, string shape, double pulseWidth)
    {
        double p = phase - Math.Floor(phase);
        return shape switch { "saw" => 2 * p - 1 - blep(p, step), "pulse" or "square" => (p < pulseWidth ? 1 : -1) + blep(p, step) - blep((p - pulseWidth) - Math.Floor(p - pulseWidth), step), "triangle" => 1 - 4 * Math.Abs(p - .5), _ => Math.Sin(Math.Tau * p) };
    }
    public double blep(double t, double step)
    {
        double dt = Math.Clamp(step, .000001, .49);
        if (t < dt) { double x = t / dt; return x + x - x * x - 1; }
        if (t > 1 - dt) { double x = (t - 1) / dt; return x * x + x + x + 1; }
        return 0;
    }
    public double modulation(GArray modulators, string target, double t, double duration, long seed)
    {
        double result = 0;
        foreach (var raw in modulators)
        {
            if (raw.VariantType != Variant.Type.Dictionary) continue;
            var entry = raw.AsGodotDictionary(); if (!Get(entry, "enabled", true).AsBool() || Get(entry, "target", "").AsString() != target) continue;
            double speed = Math.Clamp(finite(Get(entry, "rate", 1.0), 1), 0, 100), value = 0;
            switch (Get(entry, "kind", "lfo").AsString())
            {
                case "lfo": value = Math.Sin(Math.Tau * speed * t + finite(Get(entry, "phase", 0.0), 0)); break;
                case "envelope": value = Math.Pow(Math.Clamp(t / Math.Max(duration, .001), 0, 1), Math.Max(.1, finite(Get(entry, "curve", 1.0), 1))); break;
                case "random": long index = (long)Math.Floor(t * speed); value = Math.Sin(unchecked(index * 7919 + seed * 104729) * .0131) * .5 + Math.Sin(unchecked(index * 3571 + seed) * .071) * .5; break;
                case "step": var values = Get(entry, "values", new GArray { 0.0 }).AsGodotArray(); if (values.Count > 0) { long cell = (long)Math.Floor(t * speed); int i = (int)((cell % values.Count + values.Count) % values.Count); value = finite(values[i], 0); } break;
                case "velocity": value = Math.Clamp(finite(Get(entry, "velocity", 1.0), 1), 0, 1); break;
                case "automation":
                    var points = Get(entry, "points", new GArray()).AsGodotArray();
                    for (int j = 0; j < points.Count; ++j)
                    {
                        var point = points[j].AsGodotDictionary(); double a = finite(Get(point, "time", 0.0), 0);
                        if (t >= a) value = finite(Get(point, "value", 0.0), 0);
                        if (j + 1 >= points.Count) continue;
                        var next = points[j + 1].AsGodotDictionary(); double b = finite(Get(next, "time", 0.0), 0);
                        if (t >= a && t < b) { value = Mathf.Lerp(finite(Get(point, "value", 0.0), 0), finite(Get(next, "value", 0.0), 0), (t - a) / Math.Max(.000001, b - a)); break; }
                    }
                    break;
            }
            result += value * finite(Get(entry, "amount", 1.0), 1);
        }
        return result;
    }
    public Settings parameter(string id, string label, double value, double low, double high) => new Settings { ["id"] = id, ["label"] = label, ["default"] = value, ["min"] = low, ["max"] = high };
    public Godot.Collections.Array<Settings> presets()
    {
        var result = new Godot.Collections.Array<Settings>();
        foreach (var raw in Json.ParseString(CatalogJson).AsGodotArray())
        {
            var row = raw.AsGodotArray(); string kind = row[3].AsString(); string[] names = { "Pitch", "Brightness", "Density" };
            if (kind is "metal" or "wood" or "glass" or "thump" or "pop" or "subdrop" or "sting" or "click") names[2] = "Decay";
            else if (kind is "confirm" or "cancel" or "notify" or "logo") names[2] = "Spacing";
            if (kind is "explosion" or "thunder") names = new[] { "Body pitch", "Sharpness", "Debris / crack" };
            else if (kind == "boing") names = new[] { "Pitch", "Elasticity", "Bounce" };
            else if (kind is "laser" or "plasma") names = new[] { "Pitch", "Sweep", "Energy" };
            result.Add(new Settings { ["id"] = row[0], ["label"] = row[1], ["category"] = row[2], ["description"] = row[8], ["parameters"] = new GArray { parameter("duration", "Duration (seconds)", row[4].AsDouble(), .03, 60), parameter("pitch", names[0], row[5].AsDouble(), 20, 8000), parameter("character", names[1], row[6].AsDouble(), 0, 1), parameter("density", names[2], row[7].AsDouble(), 0, 1), parameter("power", "Power", .75, 0, 1), parameter("distance", "Distance", 0, 0, 1) } });
        }
        return result;
    }
    public Settings preset(string id) { foreach (var entry in presets()) if (entry["id"].AsString() == id) return entry; return new Settings(); }
    public Settings default_settings(string id) { var result = new Settings(); var entry = preset(id); foreach (var raw in Get(entry, "parameters", new GArray()).AsGodotArray()) { var p = raw.AsGodotDictionary(); result[p["id"]] = p["default"]; } return result; }
    public AudioStreamWav pcm(float[] samples, int rate, bool stereo)
    {
        double maximum = 0; foreach (float value in samples) if (float.IsFinite(value)) maximum = Math.Max(maximum, Math.Abs(value));
        double gain = maximum > .96 ? .96 / maximum : 1; var bytes = new byte[checked(samples.Length * 2)];
        for (int i = 0; i < samples.Length; ++i) { double value = float.IsFinite(samples[i]) ? samples[i] : 0; short sample = (short)Math.Round(Math.Clamp(value * gain, -.96, .96) * 32767, MidpointRounding.AwayFromZero); System.Buffers.Binary.BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i * 2, 2), sample); }
        return new AudioStreamWav { Format = AudioStreamWav.FormatEnum.Format16Bits, MixRate = Math.Clamp(rate, 8000, 192000), Stereo = stereo, Data = bytes };
    }
    public Error save_preset(string path, Settings data)
    {
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Write); if (file == null) return Godot.FileAccess.GetOpenError(); file.StoreString(Json.Stringify(new Settings { ["format"] = "kiwi.audio.preset", ["version"] = 1, ["data"] = data }, "\t")); return Error.Ok;
    }
    public Settings load_preset(string path)
    {
        if (!Godot.FileAccess.FileExists(path)) return new Settings(); var raw = Json.ParseString(Godot.FileAccess.GetFileAsString(path)); if (raw.VariantType != Variant.Type.Dictionary) return new Settings(); var parsed = raw.AsGodotDictionary();
        if (Get(parsed, "format", "").AsString() != "kiwi.audio.preset" || Get(parsed, "version", 0).AsInt32() != 1) return new Settings(); var data = Get(parsed, "data", new Settings()); return data.VariantType == Variant.Type.Dictionary ? data.AsGodotDictionary() : new Settings();
    }
}
