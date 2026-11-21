using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioInstrumentOperations
{
    private static readonly double[] DefaultHarmonics = { 1, .3, .2 }, DefaultModes = { 1, 1.48, 2.756, 4.2 }, MetallicModes = { 3100, 4517, 5971 };
    public AudioStreamWav? render_notes(GArray notes, Settings instrument, double bpm, int rate, RefCounted? job, GArray tempos, double tempoScale)
    {
        if (notes.Count > 8192) return null;
        var patch = default_instrument(Get(instrument, "id", "poly").AsString()); patch.Merge(instrument, true);
        int sampleRate = Math.Clamp(rate, 8000, 192000); using var maps = new AudioTempoMapOperations(); using var synth = new AudioSynthesisOperations(); using var cache = new AudioSourceCacheOperations();
        using var timing = KiwiAudioTempoMap.create(tempos,bpm,tempoScale); if (timing.Get("error").AsString().Length > 0) return null;
        double beatLimit = maps.seconds_to_beat(timing, 300), attack = number(patch, "attack", .01, .0005, 20), decay = number(patch, "decay", .2, .001, 20), sustain = number(patch, "sustain", .6, 0, 1), release = number(patch, "release", .2, .003, 30), duration = .01;
        var clean = new System.Collections.Generic.List<Settings>(); using var noteRng = new RandomNumberGenerator { Seed = unchecked((ulong)Get(patch, "seed", 1).AsInt64()) };
        var sampleCache = new System.Collections.Generic.Dictionary<string, Vector2[]>(); string kind = Get(patch, "kind", "subtractive").AsString();
        foreach (var raw in notes)
        {
            if (raw.VariantType != Variant.Type.Dictionary) continue; var entry = raw.AsGodotDictionary(); if (!Get(entry, "enabled", true).AsBool() || Get(entry, "mute", false).AsBool() || noteRng.Randf() > number(entry, "probability", 1, 0, 1)) continue;
            var note = entry.Duplicate(true); double start = Math.Max(0, Finite(Get(note, "start", 0.0), 0)), gate = Math.Max(0, Finite(Get(note, "duration", .25), .25));
            if (start > beatLimit || maps.beat_to_seconds(timing, start + gate) > 300) return null;
            int pitch = Math.Clamp((int)Get(note, "pitch", 60).AsDouble(), 0, 127); double velocity = Math.Clamp(number(note, "velocity", .8, 0, 1) * (Get(note, "accent", false).AsBool() ? 1.2 : 1), 0, 1);
            note["start"] = start; note["duration"] = gate; note["pitch"] = pitch; note["velocity"] = velocity; note["pan"] = number(note, "pan", 0, -1, 1); if (velocity <= 0) continue;
            var mapping = sample_mapping(patch, pitch, velocity);
            if (kind is "sampler" or "multisample")
            {
                if (mapping.Count == 0) return null; var sourceValue = Get(mapping, "sample", Get(patch, "sample", "")); string key = sourceValue.VariantType == Variant.Type.Object && sourceValue.AsGodotObject() is Resource sourceResource ? sourceResource.GetInstanceId().ToString() : sourceValue.AsString();
                if (!sampleCache.TryGetValue(key, out var data))
                {
                    var source = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("source", sourceValue).As<AudioStream>(); if (source == null) return null;
                    var decoded = cache.decode(source, sampleRate, 0, Math.Min(source.GetLength(), 300), 300); if (Get(decoded, "error", "").AsString().Length > 0) return null; data = decoded["samples"].AsVector2Array(); sampleCache[key] = data;
                }
                if (data.Length < 2) return null; note["_sample_key"] = key; int root = (int)Get(mapping, "root_pitch", Get(patch, "root_pitch", 60)).AsDouble(); note["_root"] = root;
                if (Get(patch, "one_shot", false).AsBool()) { double seconds = data.Length / (double)sampleRate / Math.Pow(2, (pitch - root) / 12.0); gate = maps.seconds_to_beat(timing, maps.beat_to_seconds(timing, start) + seconds) - start; note["duration"] = gate; }
            }
            int ratchets = Math.Clamp((int)Get(note, "ratchets", 1).AsDouble(), 1, 8);
            for (int ratchet = 0; ratchet < ratchets; ++ratchet)
            {
                if (clean.Count >= 8192) return null; var repeated = note.Duplicate(true); double repeatedStart = start + ratchet * gate / ratchets, repeatedDuration = gate / ratchets, seconds = maps.beat_to_seconds(timing, repeatedStart), gateSeconds = Math.Max(1.0 / sampleRate, maps.beat_to_seconds(timing, repeatedStart + repeatedDuration) - seconds);
                repeated["start"] = repeatedStart; repeated["duration"] = repeatedDuration; repeated["_start_seconds"] = seconds; repeated["_gate_seconds"] = gateSeconds; clean.Add(repeated); duration = Math.Max(duration, seconds + gateSeconds + release);
            }
        }
        clean.Sort((a, b) => a["start"].AsDouble().CompareTo(b["start"].AsDouble())); if (duration > 300) return null;
        if (Get(patch, "mono", false).AsBool()) for (int i = 0; i + 1 < clean.Count; ++i) clean[i]["_gate_seconds"] = Math.Max(1.0 / sampleRate, Math.Min(clean[i]["_gate_seconds"].AsDouble(), clean[i + 1]["_start_seconds"].AsDouble() - clean[i]["_start_seconds"].AsDouble()));
        double evaluations = 0; foreach (var note in clean) evaluations += (note["_gate_seconds"].AsDouble() + release) * sampleRate; if (evaluations > 64000000) return null;
        int totalFrames = Math.Max(2, (int)Math.Ceiling(Math.Min(duration, 300) * sampleRate)); var mix = new Vector2[totalFrames]; const double tau = Math.Tau;
        for (int noteIndex = 0; noteIndex < clean.Count; ++noteIndex)
        {
            if (job != null) { if (job.Call("is_cancelled").AsBool()) return null; job.Call("update", (double)noteIndex / Math.Max(1, clean.Count), "Rendering instrument notes"); }
            var note = clean[noteIndex]; int start = (int)Math.Round(note["_start_seconds"].AsDouble() * sampleRate, MidpointRounding.AwayFromZero); if (start >= totalFrames) continue;
            double gate = note["_gate_seconds"].AsDouble(), hz = midi_frequency(note["pitch"].AsDouble()), detune = number(patch, "detune", 0, 0, 50), width = number(patch, "width", 0, 0, 1), vibrato = number(patch, "vibrato", 0, 0, 2), vibratoRate = number(patch, "vibrato_rate", 5, .05, 20), velocity = note["velocity"].AsDouble(), gain = number(patch, "gain", .55, 0, 2) * Math.Pow(velocity, 1.3), pan = note["pan"].AsDouble();
            int frames = Math.Min(totalFrames - start, Math.Max(2, (int)Math.Ceiling((gate + release) * sampleRate))); var panGains = new Vector2((float)Math.Sqrt((1 - pan) * .5), (float)Math.Sqrt((1 + pan) * .5));
            double phase = 0, phaseRight = 0; var stateLeft = new double[4]; var stateRight = new double[4]; var coeff = lowpass_coeff(number(patch, "filter", 6000, 20, sampleRate * .44), number(patch, "resonance", 0, 0, .95), sampleRate);
            long seed = Get(patch, "seed", 1).AsInt64(); using var rng = new RandomNumberGenerator { Seed = unchecked((ulong)(seed + note["pitch"].AsInt64() * 7919 + (long)(note["start"].AsDouble() * 480) * 31)) };
            var delay = kind == "pluck" ? new float[Math.Max(2, (int)(sampleRate / hz))] : Array.Empty<float>(); for (int j = 0; j < delay.Length; ++j) delay[j] = rng.RandfRange(-1, 1); int delayPosition = 0;
            var data = note.TryGetValue("_sample_key", out var sampleKey) ? sampleCache[sampleKey.AsString()] : Array.Empty<Vector2>(); double sampleRatio = Math.Pow(2, (note["pitch"].AsDouble() - Get(note, "_root", 60).AsDouble()) / 12);
            var mods = Get(patch, "modulators", new GArray()).AsGodotArray().Duplicate(true); bool panModulated = false;
            foreach (var raw in mods) { var mod = raw.AsGodotDictionary(); if (Get(mod, "target", "").AsString() == "pan" && Get(mod, "enabled", true).AsBool()) panModulated = true; if (Get(mod, "kind", "").AsString() == "velocity") mod["velocity"] = velocity; }
            var bends = Get(note, "pitch_bend", new GArray()).AsGodotArray();
            var harmonics = Get(patch, "harmonics", new GArray()).AsGodotArray(); double[] partials = new double[harmonics.Count]; for (int k = 0; k < partials.Length; ++k) partials[k] = Finite(harmonics[k], kind == "modal" ? 1 : 0); if (!patch.ContainsKey("harmonics")) partials = kind == "modal" ? DefaultModes : DefaultHarmonics;
            var wavetable = Get(patch, "wavetable", new GArray()).AsGodotArray(); string shape = Get(patch, "wave", "saw").AsString(); double pulseWidth = number(patch, "pulse_width", .5, .05, .95);
            for (int i = 0; i < frames; ++i)
            {
                if (job != null && i % 8192 == 0 && job.Call("is_cancelled").AsBool()) return null;
                double t = (double)i / sampleRate, bend = bends.Count > 0 ? note_bend(bends, maps.seconds_to_beat(timing, note["_start_seconds"].AsDouble() + t) - note["start"].AsDouble()) : 0;
                double frequency = Math.Min(hz * Math.Pow(2, (Math.Sin(t * tau * vibratoRate) * vibrato * Math.Min(1, t * 6) + bend + synth.modulation(mods, "pitch", t, gate, seed)) / 12), sampleRate * .22), step = frequency / sampleRate;
                phase += step * Math.Pow(2, -detune / 1200); phaseRight += step * Math.Pow(2, detune / 1200); double env = envelope(t, gate, attack, decay, sustain, release); var value = Vector2.Zero;
                switch (kind)
                {
                    case "subtractive": value = new Vector2((float)synth.wave(phase, step, shape, pulseWidth), (float)synth.wave(phaseRight, step, shape, pulseWidth)); break;
                    case "fm": double ratio = number(patch, "ratio", 2, .25, 10), index = number(patch, "modulation", 2, 0, 8) * Math.Exp(-t / Math.Max(.02, decay)) * (.2 + .8 * velocity); value = new Vector2((float)Math.Sin(tau * phase + Math.Sin(tau * phase * ratio) * index), (float)Math.Sin(tau * phaseRight + Math.Sin(tau * phaseRight * ratio) * index)); break;
                    case "additive": double total = 0; for (int k = 0; k < Math.Min(partials.Length, 24); ++k) { if (frequency * (k + 1) >= sampleRate * .44) break; double amount = partials[k]; total += Math.Abs(amount); value.X += (float)(Math.Sin(tau * phase * (k + 1)) * amount); value.Y += (float)(Math.Sin(tau * phaseRight * (k + 1)) * amount); } value /= (float)Math.Max(total, 1); break;
                    case "wavetable": if (wavetable.Count >= 2) value = new Vector2((float)table(wavetable, phase), (float)table(wavetable, phaseRight)); else { double position = Math.Clamp(number(patch, "table_position", .4, 0, 1) + Math.Sin(t * 2) * number(patch, "modulation", 0, 0, .5), 0, 1); value = new Vector2((float)Mathf.Lerp(Math.Sin(tau * phase), synth.wave(phase, step, "saw", .5), position), (float)Mathf.Lerp(Math.Sin(tau * phaseRight), synth.wave(phaseRight, step, "saw", .5), position)); } break;
                    case "pluck": int next = (delayPosition + 1) % delay.Length; float plucked = delay[delayPosition]; delay[delayPosition] = (float)((plucked + delay[next]) * .5 * number(patch, "damping", .996, .8, .9999)); delayPosition = next; value = new Vector2(plucked, plucked); break;
                    case "modal": for (int k = 0; k < Math.Min(partials.Length, 12); ++k) { double modalHz = frequency * partials[k]; if (modalHz < sampleRate * .44) { double partial = Math.Sin(t * tau * modalHz) * Math.Exp(-t * (.6 + .5 * k)) / (k + 1); value += new Vector2((float)partial, (float)partial) * .55f; } } break;
                    case "drums":
                        double noise = rng.RandfRange(-1, 1), drum; int pitch = note["pitch"].AsInt32();
                        if (pitch is 35 or 36) drum = Math.Sin(tau * (48 * t + 2.8 * (1 - Math.Exp(-t * 30)))) * Math.Exp(-t * 11) + noise * Math.Exp(-t * 100) * .15;
                        else if (pitch is 38 or 40) drum = noise * Math.Exp(-t * 19) * .7 + Math.Sin(tau * 180 * t) * Math.Exp(-t * 22) * .3;
                        else if (pitch is 42 or 44 or 46) { double metallic = 0; foreach (double f in MetallicModes) if (f < sampleRate * .44) metallic += Math.Sin(t * tau * f) / 3; drum = (noise * .65 + metallic * .35) * Math.Exp(-t * (pitch == 46 ? 6 : 65)); }
                        else if (pitch is 49 or 51 or 57) drum = (noise * .7 + Math.Sin(t * tau * 3421) * .3) * Math.Exp(-t * 3.5);
                        else if (pitch == 39) { double clapAge = t < .072 ? t - Math.Floor(t / .018) * .018 : t - .072; drum = noise * Math.Exp(-clapAge * 50) * Math.Exp(-t * 12); }
                        else drum = Math.Sin(tau * hz * t * (1 + .15 * Math.Exp(-t * 20))) * Math.Exp(-t * 13) + noise * .15 * Math.Exp(-t * 50);
                        value = new Vector2((float)drum, (float)drum); env = Math.Min(1, t / .001) * Math.Max(0, Math.Min(1, (gate + release - t) / .006)); break;
                    case "sampler": case "multisample":
                        double samplePosition = i * sampleRatio;
                        if (Get(patch, "loop", false).AsBool())
                        {
                            double loopStart = Math.Clamp(number(patch, "loop_start", 0, 0, 300) * sampleRate, 0, Math.Max(0, data.Length - 2.0)), endSetting = Finite(Get(patch, "loop_end", -1.0), -1), loopEnd = endSetting < 0 ? data.Length - 1.0 : Math.Clamp(endSetting * sampleRate, loopStart + 1, data.Length - 1.0);
                            if (samplePosition >= loopEnd) { double range = Math.Max(1, loopEnd - loopStart); samplePosition = loopStart + (samplePosition - loopStart) - Math.Floor((samplePosition - loopStart) / range) * range; }
                            value = sample_at(data, samplePosition); double crossfade = Math.Min(sampleRate * .005, (loopEnd - loopStart) * .25);
                            if (crossfade > 0 && samplePosition > loopEnd - crossfade) value = value.Lerp(sample_at(data, loopStart + samplePosition - (loopEnd - crossfade)), (float)((samplePosition - (loopEnd - crossfade)) / crossfade));
                        }
                        else value = sample_at(data, samplePosition); break;
                }
                if (i % 64 == 0) { double cutoff = number(patch, "filter", 6000, 20, sampleRate * .44) * Math.Pow(2, number(patch, "filter_envelope", 0, -4, 6) * env + synth.modulation(mods, "cutoff", t, gate, seed)); coeff = lowpass_coeff(cutoff, number(patch, "resonance", 0, 0, .95), sampleRate); }
                value = new Vector2((float)Filter(value.X, coeff, stateLeft), (float)Filter(value.Y, coeff, stateRight)); double mono = (value.X + value.Y) * .5; value = new Vector2((float)Mathf.Lerp(mono, value.X, width), (float)Mathf.Lerp(mono, value.Y, width));
                double amplitude = Math.Clamp(1 + synth.modulation(mods, "amplitude", t, gate, seed), 0, 4);
                if (panModulated) { double movingPan = Math.Clamp(pan + synth.modulation(mods, "pan", t, gate, seed), -1, 1); panGains = new Vector2((float)Math.Sqrt((1 - movingPan) * .5), (float)Math.Sqrt((1 + movingPan) * .5)); }
                double safety = Math.Min(1, i / Math.Max(1, sampleRate * .001)) * Math.Min(1, (frames - 1 - i) / Math.Max(1, sampleRate * .003)); mix[start + i] += value * panGains * (float)(gain * env * amplitude * safety);
            }
        }
        double maximum = 0; foreach (var frame in mix) maximum = Math.Max(maximum, Math.Max(Math.Abs(frame.X), Math.Abs(frame.Y))); if (maximum > .96) for (int i = 0; i < mix.Length; ++i) mix[i] *= (float)(.96 / maximum);
        return cache.to_wav(mix, sampleRate, true);
    }
}
