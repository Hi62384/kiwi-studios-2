using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioSynthesisOperations
{
    private static readonly double[] MetalRatios = { 1, 2.756, 5.404, 8.933 }, GlassRatios = { 1, 2.32, 4.25, 6.63 }, WoodRatios = { 1, 1.47, 2.09, 3.12 }, ThunderDelays = { .13, .37, .81 }, StingIntervals = { 0, 1, 6, 13 }, CymbalRatios = { 1, 1.43, 1.93, 2.71, 3.91 };
    private static readonly int[] SparkleSemitones = { 0, 2, 4, 7, 9, 12, 14, 16 }, ChimeIntervals = { 0, 7, 12, 16 }, CancelIntervals = { 0, -5 };
    private static double Mod(double x, double y) => x - Math.Floor(x / y) * y;
    private static double Smooth(double a, double b, double x) { double t = Math.Clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
    public AudioStreamWav? generate(string id, Settings settings, long seed, int rate, RefCounted? job)
    {
        GArray? row = null; foreach (var raw in Json.ParseString(CatalogJson).AsGodotArray()) if (raw.AsGodotArray()[0].AsString() == id) { row = raw.AsGodotArray(); break; }
        if (row == null) return null;
        int sampleRate = Math.Clamp(rate, 8000, 192000); double duration = Math.Clamp(finite(Get(settings, "duration", row[4]), row[4].AsDouble()), .03, 60); int count = Math.Max(2, (int)Math.Round(duration * sampleRate, MidpointRounding.AwayFromZero));
        double pitch = Math.Clamp(finite(Get(settings, "pitch", row[5]), row[5].AsDouble()), 20, Math.Min(8000, sampleRate * .22)), color = Math.Clamp(finite(Get(settings, "character", row[6]), row[6].AsDouble()), 0, 1), density = Math.Clamp(finite(Get(settings, "density", row[7]), row[7].AsDouble()), 0, 1), power = Math.Clamp(finite(Get(settings, "power", .75), .75), 0, 1), distance = Math.Clamp(finite(Get(settings, "distance", 0.0), 0), 0, 1);
        string kind = row[3].AsString(); using var rng = new RandomNumberGenerator { Seed = unchecked((ulong)seed) }; pitch *= rng.RandfRange(.985f, 1.015f);
        var samples = new float[count]; double phase = 0, phase2 = 0, low = 0, slow = 0, band = 0, previous = 0, distanceLow = 0, timbreLow = 0, grainEnvelope = 0, grainPitch = pitch, grainPhase = 0, grainDecay = Math.Exp(-1.0 / (sampleRate * .035));
        var mods = Get(settings, "modulators", new GArray()).AsGodotArray(); bool panModulated = false;
        foreach (var raw in mods) { var item = raw.AsGodotDictionary(); if (Get(item, "target", "").AsString() == "pan" && Get(item, "enabled", true).AsBool()) panModulated = true; }
        var sampleData = Array.Empty<Vector2>();
        if (kind == "sample")
        {
            var stream = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("source", Get(settings, "sample", "")).As<AudioStream>(); if (stream == null) return null;
            using var cache = new AudioSourceCacheOperations(); var decoded = cache.decode(stream, sampleRate, 0, Math.Min(60, stream.GetLength()), 60); if (Get(decoded, "error", "").AsString().Length > 0) return null; sampleData = decoded["samples"].AsVector2Array(); if (sampleData.Length < 2) return null;
        }
        var grains = new System.Collections.Generic.List<(int Start, double Source)>(); int nextGrain = 0, grainSize = Math.Max(16, (int)(sampleRate * (.025 + .12 * color))); const double tau = Math.Tau;
        for (int i = 0; i < count; ++i)
        {
            if (job != null && i % 8192 == 0) { if (job.Call("is_cancelled").AsBool()) return null; job.Call("update", (double)i / count, "Synthesizing sound"); }
            double t = (double)i / sampleRate, u = (double)i / (count - 1), n = rng.RandfRange(-1, 1), cutoff = (160 + color * color * 10000) * Math.Pow(2, modulation(mods, "cutoff", t, duration, seed)), alpha = 1 - Math.Exp(-tau * Math.Min(cutoff, sampleRate * .42) / sampleRate);
            low += alpha * (n - low); slow += (1 - Math.Exp(-tau * 85 / sampleRate)) * (n - slow); band += (1 - Math.Exp(-tau * 1500 / sampleRate)) * ((n - low) - band);
            double frequency = pitch * Math.Pow(2, modulation(mods, "pitch", t, duration, seed) / 12);
            switch (kind)
            {
                case "thump": case "pop": frequency *= 1 + (kind == "pop" ? 2.8 : 1.8) * Math.Exp(-t * 40); break;
                case "laser": frequency *= Math.Pow(.06 + .4 * (1 - color), u); break;
                case "plasma": frequency *= .35 + 1.9 * Math.Exp(-u * 6); break;
                case "charge": case "riser": frequency *= Math.Pow(2, u * (2 + color * 3)); break;
                case "subdrop": frequency = Math.Max(22, frequency * Math.Exp(-u * (2 + color))); break;
                case "boing": frequency *= 1 + (.08 + color * .4) * Math.Sin(t * tau * (4 + 9 * density)) * Math.Exp(-u * 2); break;
                case "jump": frequency *= Math.Pow(2, u * (1 + density * 1.2)); break;
                case "whistle": frequency *= Math.Pow(2, (u * u - .5) * (1 + color * 2)); break;
                case "rubber": frequency *= .6 + u * u * 3 + .18 * Math.Sin(t * (25 + density * 60)); break;
                case "servo": frequency *= .7 + Math.Floor(u * (3 + density * 4)) * .18 + .012 * Math.Sin(t * 130); break;
                case "motor": frequency *= .65 + .35 * Math.Sin(u * Math.PI * .5) + (.003 + density * .02) * Math.Sin(t * 37); break;
                case "water": frequency *= .7 + .5 * Math.Sin(t * 5.3); break;
            }
            frequency = Math.Clamp(frequency, 12, sampleRate * .24); phase = Mod(phase + frequency / sampleRate, 1); phase2 = Mod(phase2 + frequency * 1.007 / sampleRate, 1); double tone = Math.Sin(tau * phase), value = 0;
            switch (kind)
            {
                case "thump": case "pop": value = tone * Math.Exp(-u * (kind == "thump" ? 7 : 10) * (1.6 - density)) + low * (kind == "thump" ? .35 : .08) * Math.Exp(-u * 28); break;
                case "metal": case "glass": case "wood":
                    double[] ratios = kind == "metal" ? MetalRatios : kind == "glass" ? GlassRatios : WoodRatios;
                    for (int k = 0; k < ratios.Length; ++k) { double hz = frequency * ratios[k]; if (hz < sampleRate * .44) value += Math.Sin(tau * hz * t) * Math.Exp(-u * (2.2 + k * (kind != "wood" ? .7 : 2.8)) * (1.6 - density)) / (1 + k); }
                    value = value * .48 + n * .18 * Math.Exp(-t * 180); break;
                case "explosion": case "thunder":
                    value = slow * 4 * Math.Exp(-u * 3.5) + low * .75 * Math.Exp(-u * 7) + Math.Sin(tau * pitch * t * (1 + Math.Exp(-t * 10))) * Math.Exp(-t * 5) * .45;
                    if (kind == "thunder") foreach (double delay in ThunderDelays) { double age = t - delay; if (age >= 0) value += slow * 1.7 * Math.Exp(-age * 1.5) * (1 - Math.Exp(-age * 30)); }
                    value += n * density * Math.Max(0, Math.Sin(t * 91 + Math.Sin(t * 8))) * Math.Exp(-u * 7) * .22; break;
                case "whoosh": double sweep = 1 - Math.Exp(-tau * (200 + Math.Sin(u * Math.PI) * pitch * 6) / sampleRate); previous += sweep * (n - previous); value = ((n - previous) * .35 + previous * .7 + tone * .07) * Math.Pow(Math.Sin(u * Math.PI), 1.5 + density * 3); break;
                case "steps": double stepAge = Mod(t, .65 - density * .35); value = (Math.Sin(tau * pitch * stepAge) * .65 + low * .8) * Math.Exp(-stepAge * 30) * Math.Min(stepAge * 900, 1); break;
                case "roll": case "gear": double speed = 5 + density * 24, contact = Math.Pow(Math.Max(0, Math.Sin(t * tau * speed + (kind == "roll" ? 2 * u * u : 0))), 16); value = (tone * .55 + Math.Sin(tau * phase * 3) * .15 + low * .5) * contact; break;
                case "jump": value = wave(phase, frequency / sampleRate, "triangle", .5) * Math.Exp(-u * 4) * .85; break;
                case "creak": double friction = Math.Pow(Math.Max(0, Math.Sin(t * (18 + density * 40 + 9 * Math.Sin(t * 4.2)))), 3); value = (tone + .4 * Math.Sin(t * tau * pitch * 2.37)) * friction * .48 * Math.Sin(u * Math.PI); break;
                case "scrape": value = (band * Math.Sin(t * tau * pitch) + low * Math.Sin(t * tau * pitch * 2.72)) * (.55 + .45 * Math.Sin(t * (15 + density * 40))) * Math.Sin(u * Math.PI); break;
                case "shatter": case "sparkle": case "rain": case "water": case "crackle": case "fire": case "rustle":
                    double hits = 6 + density * density * (kind is "rain" or "crackle" or "rustle" ? 450 : 42);
                    if (rng.Randf() < hits / sampleRate) { grainEnvelope = rng.RandfRange(.3f, 1); grainPitch = pitch * rng.RandfRange(.6f, 3); if (kind == "sparkle") { int semitone = SparkleSemitones[rng.RandiRange(0, 7)]; grainPitch = pitch * Math.Pow(2, semitone / 12.0); } grainPhase = 0; }
                    grainPitch = Math.Min(grainPitch, sampleRate * .4); grainPhase = Mod(grainPhase + grainPitch / sampleRate, 1); grainEnvelope *= kind != "sparkle" ? grainDecay : Math.Exp(-1.0 / (sampleRate * .16)); double grain = Math.Sin(tau * grainPhase + (kind == "water" ? 4 * grainEnvelope : 0)) * grainEnvelope; value = grain * .65;
                    if (kind == "rain") value += (n - low) * .16 + low * .1; else if (kind == "water") value += low * .4; else if (kind == "fire") value = grain * n * .6 + slow * 1.7; else if (kind is "crackle" or "rustle") value = grainEnvelope * (band * .8 + Math.Sin(tau * grainPhase) * band * .2) * (kind == "crackle" ? 1.3 : .65); else if (kind == "shatter") value = value * Math.Exp(-u * 2) + n * Math.Exp(-t * 140) * .35; break;
                case "wind": value = low * (.3 + .7 * Math.Pow(.5 + .5 * Math.Sin(t * (.5 + density * 2.5) + Math.Sin(t * .71)), 2)) + tone * .07 * (.5 + .5 * Math.Sin(t * 2)); break;
                case "insects": for (int k = 0; k < 3; ++k) { double chirp = Math.Pow(Math.Max(0, Math.Sin(t * (3 + density * 6 + k * 1.31))), 8); value += Math.Sin(t * tau * pitch * (1 + k * .17)) * chirp * (.22 / (k + 1)); } break;
                case "laser": value = (wave(phase, frequency / sampleRate, "saw", .5) * (.15 + density * .7) + tone * (.85 - density * .7)) * Math.Exp(-u * 5); break;
                case "plasma": value = Math.Sin(tau * phase + (1 + color * 5) * Math.Sin(tau * phase * 2) * Math.Exp(-u * 3)) * Math.Exp(-u * 5) * (.65 + .35 * Math.Sin(t * (80 + density * 190))); break;
                case "charge": case "riser": value = (wave(phase, frequency / sampleRate, "saw", .5) * .3 + Math.Sin(tau * phase + Math.Sin(tau * phase2) * color * 2) * .45 + low * u * .25) * Math.Pow(u, .6) * (.7 + .3 * Math.Sin(t * (5 + density * 12 + 30 * u))); break;
                case "field": value = (tone * .45 + Math.Sin(tau * phase2) * .35 + Math.Sin(t * tau * pitch * 1.5) * .2) * (.65 + .35 * Math.Sin(t * tau * (1 + density * 9))); break;
                case "spell": value = Math.Sin(tau * phase + 2 * Math.Sin(t * tau * pitch * (1 + u))) * Math.Pow(Math.Sin(u * Math.PI), 2) * .4; value += (Math.Sin(t * tau * pitch * 1.5) + Math.Sin(t * tau * pitch * 2)) * Math.Exp(-Math.Max(0, u - .55) * 6) * Smooth(.2 + density * .3, .4 + density * .3, u) * .2; break;
                case "enchant": value = (tone + .5 * Math.Sin(t * tau * pitch * 1.5) + .3 * Math.Sin(t * tau * pitch * 2)) * .35 * (.6 + .4 * Math.Sin(t * (1 + density * 4))) * Math.Sin(u * Math.PI); break;
                case "whisper": value = low * (Math.Sin(t * tau * pitch * 1.625) * .4 + Math.Sin(t * tau * pitch * (2.75 + .75 * Math.Sin(t * 1.1))) * .4) * (.4 + .6 * Math.Pow(Math.Sin(t * (2 + density * 5)), 2)); break;
                case "drone": value = (tone * .45 + Math.Sin(tau * phase2) * .3 + Math.Sin(t * tau * pitch * 2.07) * .18) * (.75 + .25 * Math.Sin(t * (.3 + density * 1.2))); break;
                case "sting": foreach (double interval in StingIntervals) value += Math.Sin(t * tau * pitch * Math.Pow(2, interval / 12)) * .22 * Math.Exp(-u * 4 * (1.6 - density)); break;
                case "heartbeat": double heartAge = Mod(t, 1 - density * .45); value = Math.Sin(tau * pitch * heartAge) * Math.Exp(-heartAge * 25) * Smooth(0, .01, heartAge); if (heartAge >= .18) value += Math.Sin(tau * pitch * 1.35 * (heartAge - .18)) * Math.Exp(-(heartAge - .18) * 35) * Smooth(.18, .19, heartAge) * .7; break;
                case "reverse": value = (tone * .45 + Math.Sin(t * tau * pitch * 2.756) * .25 + low * .3) * Math.Pow(u, 1.5 + density * 3); break;
                case "boing": value = (tone * .65 + Math.Sin(tau * phase * 2) * .2 + Math.Sin(tau * phase * 3) * .1) * Math.Exp(-u * 3.8); break;
                case "whistle": value = (tone * .7 + low * (.02 + density * .12)) * Math.Sin(u * Math.PI); break;
                case "rubber": value = Math.Sin(tau * phase + color * Math.Sin(tau * phase * 3)) * Math.Sin(u * Math.PI) * .65; break;
                case "click": value = (tone * .6 + Math.Sin(t * tau * pitch * 1.61) * .3) * Math.Exp(-u * 12 * (1.6 - density)); break;
                case "confirm": case "cancel": case "notify": case "logo":
                    int noteCount = kind == "logo" ? 4 : kind == "notify" ? 3 : 2; double spacing = duration / (noteCount + 2.0) * (.6 + density * .8); int[] intervals = kind != "cancel" ? ChimeIntervals : CancelIntervals;
                    for (int k = 0; k < noteCount; ++k) { double age = t - spacing * k, hz = pitch * Math.Pow(2, intervals[k] / 12.0); if (age >= 0 && hz < sampleRate * .4) value += (Math.Sin(tau * hz * age) + .2 * Math.Sin(tau * hz * 2.01 * age)) * Math.Exp(-age * (kind != "logo" ? 7 : 2.5)) * Smooth(0, .006, age) * .42; } break;
                case "subdrop": value = tone * Math.Exp(-u * 2.8 * (1.6 - density)) * .85; break;
                case "cymbal": foreach (double ratio in CymbalRatios) if (pitch * ratio < sampleRate * .44) value += Math.Sin(t * tau * pitch * ratio) * .1; value = (value + (n - low) * .4) * Math.Pow(u, 1 + density * 2); break;
                case "motor": value = (wave(phase, frequency / sampleRate, "saw", .5) * .45 + tone * .35 + Math.Sin(tau * phase * 4) * .12 + low * .15) * Math.Sin(u * Math.PI); break;
                case "servo": value = (wave(phase, frequency / sampleRate, "pulse", .5) * .5 + tone * .3) * Math.Pow(Math.Sin(u * Math.PI), .6); break;
                case "hydraulic": value = (low * (.3 + density * .6) + tone * (.3 - density * .2) + Math.Sin(tau * phase * 3) * .08) * Smooth(0, .2, u) * (1 - Smooth(.7, 1, u)); break;
                case "sample":
                    if (sampleData.Length > 1)
                    {
                        if (i >= nextGrain) { grains.Add((i, rng.Randf() * Math.Max(0, sampleData.Length - grainSize - 1.0))); nextGrain = i + Math.Max(1, (int)(grainSize * (.65 - density * .5))); }
                        for (int g = grains.Count - 1; g >= 0; --g) { int age = i - grains[g].Start; if (age >= grainSize) { grains.RemoveAt(g); continue; } double position = grains[g].Source + age * pitch / 440; int index = (int)position; if (index + 1 < sampleData.Length) { double a = (sampleData[index].X + sampleData[index].Y) * .5, b = (sampleData[index + 1].X + sampleData[index + 1].Y) * .5; value += Mathf.Lerp(a, b, position - index) * (.5 - .5 * Math.Cos(tau * age / grainSize)) * .45; } }
                    }
                    break;
            }
            timbreLow += alpha * (value - timbreLow); value = timbreLow; double amp = Math.Clamp(1 + modulation(mods, "amplitude", t, duration, seed), 0, 4);
            distanceLow += (1 - Math.Exp(-tau * Mathf.Lerp(16000, 450, distance) / sampleRate)) * (value - distanceLow); value = Mathf.Lerp(value, distanceLow, distance) * power * (1 - distance * .65) * amp;
            double boundary = Smooth(0, Math.Min(.004, duration * .12), t) * Smooth(0, Math.Min(.02, duration * .2), duration - t - 1.0 / sampleRate); samples[i] = double.IsFinite(value) ? (float)(value * boundary) : 0;
        }
        if (panModulated)
        {
            var stereo = new float[count * 2];
            for (int i = 0; i < count; ++i) { if (i % 8192 == 0 && job != null && job.Call("is_cancelled").AsBool()) return null; double pan = Math.Clamp(modulation(mods, "pan", (double)i / sampleRate, duration, seed), -1, 1); stereo[i * 2] = (float)(samples[i] * Math.Min(1, 1 - pan)); stereo[i * 2 + 1] = (float)(samples[i] * Math.Min(1, 1 + pan)); }
            return pcm(stereo, sampleRate, true);
        }
        return pcm(samples, sampleRate, false);
    }
    public AudioStreamWav layer(GArray layers, int rate)
    {
        int sampleRate = Math.Clamp(rate, 8000, 192000), lengthFrames = 1;
        var rendered = new System.Collections.Generic.List<(AudioStreamWav Stream, byte[] Data, long Start, int Frames, double Speed, double Volume, double Pan)>();
        for (int i = 0; i < Math.Min(32, layers.Count); ++i)
        {
            var raw = layers[i]; if (raw.VariantType != Variant.Type.Dictionary) continue; var item = raw.AsGodotDictionary(); if (Get(item, "mute", false).AsBool()) continue;
            var stream = Get(item, "stream").As<AudioStreamWav>();
            if (stream == null && item.ContainsKey("generator")) stream = generate(item["generator"].AsString(), Get(item, "settings", new Settings()).AsGodotDictionary(), Get(item, "seed", 1).AsInt64(), sampleRate, null);
            if (stream == null || stream.Format != AudioStreamWav.FormatEnum.Format16Bits) continue;
            double startValue = Math.Max(0, finite(Get(item, "start", 0.0), 0) * sampleRate);
            long start = startValue >= long.MaxValue ? long.MaxValue : (long)startValue;
            double speed = Math.Pow(2, Math.Clamp(finite(Get(item, "pitch", 0.0), 0), -48, 48) / 12);
            int frames = (int)Math.Min(stream.GetLength() * sampleRate / speed, Math.Clamp(finite(Get(item, "duration", 60.0), 60), 0, 60) * sampleRate);
            lengthFrames = (int)Math.Min(sampleRate * 60L, Math.Max(lengthFrames, start > long.MaxValue - frames ? long.MaxValue : start + frames));
            rendered.Add((stream, stream.Data, start, frames, speed, Math.Clamp(finite(Get(item, "volume", 1.0), 1), 0, 8), Math.Clamp(finite(Get(item, "pan", 0.0), 0), -1, 1)));
        }
        var mix = new float[lengthFrames * 2];
        foreach (var item in rendered)
        {
            int channels = item.Stream.Stereo ? 2 : 1, sourceFrames = item.Data.Length / (channels * 2); double leftGain = Math.Sqrt((1 - item.Pan) * .5), rightGain = Math.Sqrt((1 + item.Pan) * .5);
            for (int j = 0; j < Math.Min(item.Frames, lengthFrames - item.Start); ++j)
            {
                double position = j * (double)item.Stream.MixRate / sampleRate * item.Speed;
                if (position >= sourceFrames) break;
                int index = (int)position, next = Math.Min(index + 1, sourceFrames - 1); double blend = position - index, fade = Math.Min(1, j / Math.Max(1, sampleRate * .003)) * Math.Min(1, (item.Frames - 1 - j) / Math.Max(1, sampleRate * .006));
                for (int ch = 0; ch < 2; ++ch)
                {
                    int sourceChannel = Math.Min(ch, channels - 1); double a = System.Buffers.Binary.BinaryPrimitives.ReadInt16LittleEndian(item.Data.AsSpan((index * channels + sourceChannel) * 2, 2)) / 32768.0, b = System.Buffers.Binary.BinaryPrimitives.ReadInt16LittleEndian(item.Data.AsSpan((next * channels + sourceChannel) * 2, 2)) / 32768.0;
                    mix[((int)item.Start + j) * 2 + ch] += (float)(Mathf.Lerp(a, b, blend) * item.Volume * (ch == 0 ? leftGain : rightGain) * fade);
                }
            }
        }
        return pcm(mix, sampleRate, true);
    }
    public Godot.Collections.Array<AudioStreamWav> variations(string id, Settings settings, long seed, int count, int rate)
    {
        var result = new Godot.Collections.Array<AudioStreamWav>();
        for (int i = 0; i < Math.Clamp(count, 1, 16); ++i) result.Add(generate(id, settings, unchecked(seed + i), rate, null)!);
        return result;
    }
}
