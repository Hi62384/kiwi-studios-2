using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioRegionEditOperations : RefCounted
{
    private static readonly string[] Operations = { "copy", "cut", "paste", "trim", "silence", "amplify", "normalize", "reverse", "fade_in", "fade_out", "repair", "invert", "mono", "time_stretch", "pitch_shift", "set_amplitude" };
    private static Settings Failure(string message) => new Settings { ["error"] = message };
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(new StringName(key), out var found) ? found : fallback;
    private static bool Cancelled(RefCounted? job) => job != null && job.Call("is_cancelled").AsBool();
    public string unsupported_reason(GodotObject clip, GodotObject actor, string operation)
    {
        double start = clip.Get("start_time").AsDouble(), offset = clip.Get("source_offset").AsDouble(), duration = clip.Get("duration").AsDouble(), speed = clip.Get("playback_speed").AsDouble();
        if (!double.IsFinite(start) || !double.IsFinite(offset) || !double.IsFinite(duration) || !double.IsFinite(speed) || start < 0 || offset < 0 || duration <= 0 || speed <= 0) return "The clip has invalid source geometry.";
        if (operation == "copy") return "";
        var values = actor.Get("values").AsGodotDictionary();
        if (Get(values, "reverse", false).AsBool()) return "Render the reversed clip in place before sample-selection editing.";
        if (Get(values, "loop", false).AsBool()) return "Render the looped clip in place before sample-selection editing.";
        if (Get(values, "effects", new GArray()).AsGodotArray().Count > 0) return "Render or remove the clip effects before sample-selection editing; splitting would restart their processing state. Track effects can remain.";
        if (Get(values, "automation", new Settings()).AsGodotDictionary().Count > 0 || actor.Get("animation_tracks").AsGodotArray().Count > 0) return "Render or remove clip automation before sample-selection editing so its timing is preserved.";
        if (!Mathf.IsEqualApprox(Get(values, "pitch", 1.0).AsDouble(), 1)) return "Render the pitch-processed clip in place before sample-selection editing.";
        using var edits = new AudioEditSessionOperations(); return edits.is_note_source(actor) ? "Render the instrument pattern in place before editing its audio samples." : "";
    }
    public Vector2[] resample(Vector2[] samples, int fromRate, int toRate, int count)
    {
        if (fromRate == toRate) return samples;
        var output = new Vector2[count];
        for (int i = 0; i < count; ++i) { double position = (double)i * fromRate / toRate; int first = Math.Min((int)Math.Floor(position), samples.Length - 1), second = Math.Min(first + 1, samples.Length - 1); output[i] = samples[first].Lerp(samples[second], (float)(position - first)); }
        return output;
    }
    public Settings prepare(GodotObject? clip, GodotObject? actor, AudioStream? stream, string operation, Vector2I selection, int rate, double amount, int channel, Vector2[] clipboard, int clipboardRate, RefCounted? job)
    {
        if (clip == null || actor == null || stream == null) return Failure("The selected audio source is missing.");
        if (Array.IndexOf(Operations, operation) < 0) return Failure("Unknown sample-selection operation.");
        if (rate < 8000 || rate > 192000) return Failure("This source sample rate is not supported for sample-selection editing (8–192 kHz).");
        if (channel < -1 || channel > 1 || !double.IsFinite(amount)) return Failure("Invalid sample-edit settings.");
        if (operation == "set_amplitude" && (amount < -1 || amount > 1)) return Failure("Sample amplitude must be between -1 and 1.");
        if (channel >= 0 && operation is "cut" or "paste" or "trim" or "time_stretch") return Failure("Choose Stereo for duration-changing edits so both channels stay aligned.");
        string reason = unsupported_reason(clip, actor, operation); if (reason.Length > 0) return Failure(reason);
        if (Cancelled(job)) return Failure("Cancelled.");
        double offset = clip.Get("source_offset").AsDouble(), speed = clip.Get("playback_speed").AsDouble(), duration = clip.Get("duration").AsDouble(), sourceEnd = offset + duration * speed;
        if (sourceEnd > stream.GetLength() + 1.0 / rate) return Failure("The clip extends past its source. Trim or render it before sample editing.");
        double minimumFrame = Math.Ceiling(offset * rate - .000001), maximumFrame = Math.Floor(Math.Min(sourceEnd, stream.GetLength()) * rate + .000001);
        if (minimumFrame > int.MaxValue) return Failure("This source window is beyond the sample-selection coordinate limit. Render the clip in place before sample editing.");
        int minimum = (int)minimumFrame, maximum = (int)Math.Min(int.MaxValue, maximumFrame);
        if (maximum < minimum) return Failure("The clip is shorter than one source sample.");
        if (selection.Y < selection.X || selection.X < minimum - 1 || selection.Y > maximum + 1) return Failure("Select a region inside the opened clip before editing.");
        int first = Math.Clamp(selection.X, minimum, maximum), last = Math.Clamp(selection.Y, first, maximum), count = last - first;
        if (count == 0 && operation != "paste") return Failure("Select audio to process.");
        if (operation == "paste" && clipboard.Length == 0) return Failure("Copy or cut some audio before pasting.");
        var result = new Settings { ["error"] = "", ["operation"] = operation, ["clip_id"] = clip.Get("id"), ["source_reference"] = Get(actor.Get("values").AsGodotDictionary(), "audio"), ["source_stream"] = stream, ["start_time"] = clip.Get("start_time"), ["source_offset"] = offset, ["duration"] = duration, ["playback_speed"] = speed, ["first"] = first, ["last"] = last, ["rate"] = rate, ["selection"] = new Vector2I(first, last), ["inserted_frames"] = 0, ["working_bytes"] = 0 };
        if (operation == "trim") return result;
        int outputCount = count;
        if (operation is "cut" or "copy") outputCount = 0;
        if (operation == "paste")
        {
            int fromRate = clipboardRate > 0 ? clipboardRate : rate; if (fromRate < 8000 || fromRate > 192000) return Failure("The copied audio has an unsupported sample rate.");
            double frames = Math.Max(1, Math.Round((double)clipboard.Length * rate / fromRate, MidpointRounding.AwayFromZero));
            if (frames > (32L * 1024 * 1024 - 65536) / 24) return Failure("This selection exceeds the 32 MiB sample-edit working budget. Select a shorter region; the untouched source can be any length.");
            outputCount = (int)frames;
        }
        else if (operation == "time_stretch") { double frames = Math.Max(1, Math.Round(count * Math.Clamp(amount, .25, 4), MidpointRounding.AwayFromZero)); if (frames > int.MaxValue) return Failure("This selection exceeds the 32 MiB sample-edit working budget. Select a shorter region; the untouched source can be any length."); outputCount = (int)frames; }
        long workingBytes = operation is "cut" or "copy" ? (count + 2L) * 8 + 65536 : operation == "paste" ? outputCount * 24L + 65536 : (count + 2L) * 32 + outputCount * 24L + 65536;
        if (workingBytes > 32L * 1024 * 1024) return Failure("This selection exceeds the 32 MiB sample-edit working budget. Select a shorter region; the untouched source can be any length.");
        result["working_bytes"] = workingBytes; result["inserted_frames"] = outputCount; job?.Call("update", .1, "Processing selected samples only");
        using var cache = new AudioSourceCacheOperations();
        if (operation == "paste") { var pasted = resample(clipboard, clipboardRate > 0 ? clipboardRate : rate, rate, outputCount); if (Cancelled(job)) return Failure("Cancelled."); result["stream"] = cache.to_wav(pasted, rate, true); return result; }
        int decodeFirst = operation == "repair" ? Math.Max(0, first - 1) : first, decodeLast = operation == "repair" ? (int)Math.Min(Math.Round(stream.GetLength() * rate, MidpointRounding.AwayFromZero), (long)last + 1) : last;
        var decoded = cache.decode(stream, rate, (double)decodeFirst / rate, (double)(decodeLast - decodeFirst) / rate, (double)(decodeLast - decodeFirst + 1) / rate);
        if (Get(decoded, "error", "").AsString().Length > 0) return decoded;
        var samples = decoded["samples"].AsVector2Array(); if (samples.Length != decodeLast - decodeFirst) return Failure("The decoder returned an incomplete selection. No audio was changed.");
        if (Cancelled(job)) return Failure("Cancelled.");
        if (operation is "copy" or "cut") { result["clipboard"] = samples; result["clipboard_rate"] = rate; return result; }
        using var analysis = new AudioAnalysisOperations(); Vector2[] output;
        if (operation is "time_stretch" or "pitch_shift") { var transformed = analysis.transform_selection(samples, operation, 0, count, amount, channel, rate, job); if (Get(transformed, "error", "").AsString().Length > 0) return transformed; output = transformed["samples"].AsVector2Array(); result["inserted_frames"] = transformed["inserted_frames"]; }
        else { int local = first - decodeFirst; output = analysis.edit(samples, operation, local, local + count, amount, channel, Array.Empty<Vector2>()); if (decodeFirst != first || decodeLast != last) output = output.AsSpan(local, count).ToArray(); }
        if (Cancelled(job)) return Failure("Cancelled."); result["stream"] = cache.to_wav(output, rate, true); return result;
    }
    public Settings piece(GodotObject actor, Resource clip, double at, double offset, double duration)
    {
        var copy = new ActorData();
        string Id() { using var crypto = new Crypto(); return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant(); }
        copy.Set("id", Id()); foreach (string key in new[] { "type_id", "display_name", "parent_id", "section_id", "show_timeline_children", "link_timeline_children", "schema_version" }) copy.Set(key, actor.Get(key));
        var values = actor.Get("values").AsGodotDictionary().Duplicate(true); values[new StringName("fade_in")] = 0.0; values[new StringName("fade_out")] = 0.0; copy.Set("values", values);
        var part = clip.Duplicate(false); part.Set("id", Id()); part.Set("actor_id", copy.Get("id")); part.Set("start_time", at); part.Set("source_offset", offset); part.Set("duration", duration);
        return new Settings { ["actor"] = copy, ["clip"] = part };
    }
    private static bool SameSource(Variant a, Variant b) => a.VariantType == b.VariantType && (a.VariantType == Variant.Type.String ? a.AsString() == b.AsString() : a.VariantType == Variant.Type.Object ? a.AsGodotObject() == b.AsGodotObject() : a.Equals(b));
    public Settings apply(RefCounted session, Settings result)
    {
        if (Get(result, "error", "").AsString().Length > 0) return result;
        string id = Get(result, "clip_id", "").AsString(); using var edits = new AudioEditSessionOperations();
        if (!edits.can_edit(session, id)) return Failure("The clip's track is locked or unavailable. No audio was changed.");
        var document = session.Get("document").AsGodotObject(); var track = document.Call("track_for_clip", id).AsGodotDictionary();
        if (track.ContainsKey("frozen_track") || track.ContainsKey("frozen_source")) return Failure("Unfreeze the track before sample editing. No audio was changed.");
        var clip = document.Call("clip_for_id", id).As<Resource>(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        if (clip == null || actor == null) return Failure("The edited clip no longer exists.");
        if (session.Get("_before").VariantType != Variant.Type.Nil) return Failure("Finish the current adjustment and apply the selection edit again.");
        var values = actor.Get("values").AsGodotDictionary();
        bool geometry = true; foreach (string key in new[] { "start_time", "source_offset", "duration", "playback_speed" }) if (clip.Get(key).AsDouble() != result[key].AsDouble()) geometry = false;
        if (!SameSource(Get(values, "audio"), Get(result, "source_reference")) || !geometry) return Failure("The clip or its source changed during processing. Apply the selection edit again.");
        if (GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("source", Get(values, "audio")).AsGodotObject() != Get(result, "source_stream").AsGodotObject()) return Failure("The source file changed during processing. Reopen the waveform before editing.");
        string operation = result["operation"].AsString(), reason = unsupported_reason(clip, actor, operation); if (reason.Length > 0) return Failure(reason);
        Settings Success(string focus, Godot.Collections.Array<string> ids) => new Settings { ["error"] = "", ["focus_clip_id"] = focus, ["clip_ids"] = ids };
        if (operation == "copy") return Success(id, new Godot.Collections.Array<string> { id });
        int rate = result["rate"].AsInt32(); double first = result["first"].AsDouble() / rate, last = result["last"].AsDouble() / rate, speed = clip.Get("playback_speed").AsDouble();
        var selected = session.Get("selected_ids").AsGodotArray();
        if (operation == "trim")
        {
            edits.begin(session, "Trim waveform selection"); clip.Set("source_offset", first); clip.Set("duration", (last - first) / speed); selected.Clear(); selected.Add(id); edits.commit(session); session.EmitSignal("selection_changed"); return Success(id, new Godot.Collections.Array<string> { id });
        }
        double offset = clip.Get("source_offset").AsDouble(), duration = clip.Get("duration").AsDouble(), sourceEnd = offset + duration * speed, at = clip.Get("start_time").AsDouble();
        var parts = new System.Collections.Generic.List<Settings>();
        if (first > offset + .000000001) { var left = piece(actor, clip, at, offset, (first - offset) / speed); parts.Add(left); at += left["clip"].AsGodotObject().Get("duration").AsDouble(); }
        int focusIndex = parts.Count;
        if (operation != "cut")
        {
            var edited = Get(result, "stream").As<AudioStreamWav>(); long frames = Get(result, "inserted_frames", 0).AsInt64();
            if (edited == null || frames <= 0) return Failure("The edit produced no audio. No source was changed.");
            var middle = piece(actor, clip, at, 0, (double)frames / rate / speed); var middleValues = middle["actor"].AsGodotObject().Get("values").AsGodotDictionary();
            middleValues[new StringName("original_audio")] = Get(values, "original_audio", Get(values, "audio")); middleValues[new StringName("audio")] = edited; middleValues[new StringName("source_duration")] = edited.GetLength(); middleValues.Remove(new StringName("transients")); middleValues.Remove(new StringName("transients_source_identity"));
            parts.Add(middle); at += middle["clip"].AsGodotObject().Get("duration").AsDouble();
        }
        if (last < sourceEnd - .000000001) parts.Add(piece(actor, clip, at, last, (sourceEnd - last) / speed));
        if (parts.Count > 0)
        {
            double fadeIn = Math.Min(Get(values, "fade_in", 0.0).AsDouble(), duration), fadeOut = Math.Min(Get(values, "fade_out", 0.0).AsDouble(), duration);
            if (parts.Count > 1 && (parts[0]["clip"].AsGodotObject().Get("duration").AsDouble() + .000000001 < fadeIn || parts[^1]["clip"].AsGodotObject().Get("duration").AsDouble() + .000000001 < fadeOut)) return Failure("This selection crosses a clip fade. Shorten or remove the clip fade, or render the clip in place before editing.");
            parts[0]["actor"].AsGodotObject().Get("values").AsGodotDictionary()[new StringName("fade_in")] = fadeIn;
            parts[^1]["actor"].AsGodotObject().Get("values").AsGodotDictionary()[new StringName("fade_out")] = fadeOut;
            focusIndex = Math.Min(focusIndex, parts.Count - 1); parts[focusIndex]["clip"].AsGodotObject().Set("id", clip.Get("id")); parts[focusIndex]["clip"].AsGodotObject().Set("actor_id", actor.Get("id")); parts[focusIndex]["actor"].AsGodotObject().Set("id", actor.Get("id"));
        }
        var ids = new Godot.Collections.Array<string>(); foreach (var part in parts) ids.Add(part["clip"].AsGodotObject().Get("id").AsString());
        string focusId = ids.Count > 0 ? ids[focusIndex] : "";
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray(); int index = clips.IndexOf(clip);
        if (index < 0) return Failure("The selected clip is no longer in this document.");
        edits.begin(session, "Edit waveform " + operation); clips.RemoveAt(index); actors.RemoveAt(index);
        for (int i = 0; i < parts.Count; ++i) { clips.Insert(index + i, parts[i]["clip"]); actors.Insert(index + i, parts[i]["actor"]); }
        selected.Clear(); if (focusId.Length > 0) selected.Add(focusId); edits.commit(session); session.EmitSignal("selection_changed"); return Success(focusId, ids);
    }
}
