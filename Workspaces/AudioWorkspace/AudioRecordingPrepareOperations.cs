using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class AudioRecordingPrepareOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(new StringName(key), out var v) ? v : fallback;
    private static bool Cancelled(RefCounted? job) => job != null && job.Call("is_cancelled").AsBool();
    public string signature(GodotObject document)
    {
        var parts = new GArray(); foreach (string key in new[] { "tempo", "time_signature", "tempo_points", "meter_points", "note_base_tempo", "note_base_meter", "master", "tracks", "loop_start", "loop_end" }) parts.Add(document.Get(key));
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray(); using var edits = new AudioEditSessionOperations();
        for (int i = 0; i < Math.Min(clips.Count, actors.Count); ++i) { var clip = clips[i].AsGodotObject(); var actor = actors[i].AsGodotObject(); var source = actor.Get("values").AsGodotDictionary(); if (Get(source, "muted", false).AsBool()) continue; var values = source.Duplicate(true); foreach (string key in new[] { "notes_dirty", "rendered_signature", "transients", "transients_source_identity", "original_audio" }) values.Remove(new StringName(key)); if (edits.is_note_source(actor)) { values.Remove(new StringName("audio")); values.Remove(new StringName("source_duration")); } parts.Add(new GArray { clip.Get("id"), clip.Get("actor_id"), clip.Get("start_time"), clip.Get("source_offset"), clip.Get("duration"), clip.Get("playback_speed"), clip.Get("layer"), values }); }
        return GD.VarToStr(stable_value(parts, 0)).Sha256Text();
    }
    public Variant stable_value(Variant value, int depth)
    {
        if (depth > 24) return "depth_limit";
        if (value.VariantType == Variant.Type.Object && value.AsGodotObject() is Resource resource) return new Settings { ["resource_id"] = resource.GetInstanceId(), ["resource_path"] = resource.ResourcePath };
        if (value.VariantType == Variant.Type.Dictionary) { var source = value.AsGodotDictionary(); var output = new Settings(); foreach (var key in source.Keys) output[key] = stable_value(source[key], depth + 1); return output; }
        if (value.VariantType == Variant.Type.Array) { var output = new GArray(); foreach (var item in value.AsGodotArray()) output.Add(stable_value(item, depth + 1)); return output; }
        if (value.VariantType == Variant.Type.String && value.AsString().GetExtension().ToLowerInvariant() is "wav" or "mp3" or "ogg" or "flac") { string path = value.AsString(); using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read); long length = file != null ? (long)file.GetLength() : -1; return new Settings { ["source_path"] = path, ["modified"] = length >= 0 ? (long)Godot.FileAccess.GetModifiedTime(path) : -1, ["bytes"] = length }; }
        return value;
    }
    public void initialize_backing(RefCounted backing, string directory)
    {
        string root = ProjectSettings.GlobalizePath("user://audio_workspace/recording_previews").Replace('\\', '/').SimplifyPath(), normalized = directory.Replace('\\', '/').SimplifyPath(); if (directory.Length > 0 && normalized.GetBaseDir() == root) { backing.Set("_directory", normalized); backing.Set("path", normalized.PathJoin("mix.wav")); }
    }
    public bool backing_valid(RefCounted backing)
    {
        var info = backing.Get("info").AsGodotDictionary(); if (backing.Get("_directory").AsString().Length == 0 || Get(info, "error", "invalid").AsString().Length > 0) return false; using var pcm = new AudioPcmFileOperations(); var current = pcm.inspect(backing.Get("path").AsString()); return Get(current, "error", "invalid").AsString().Length == 0 && current.RecursiveEqual(info);
    }
    public void release_directory(string directory)
    {
        if (directory.Length == 0) return; using var renderer = new AudioRendererOperations(); var remaining = renderer.remove_owned(directory); if (remaining.Length > 0) GD.PushWarning("Could not remove released recording backing: " + string.Join("; ", remaining));
    }
    public void release_backing(RefCounted backing)
    {
        string directory = backing.Get("_directory").AsString(); if (directory.Length == 0) return; release_directory(directory); backing.Set("_directory", "");
    }
    public Settings prepare(RefCounted document, double start, double end, RefCounted? job)
    {
        Settings Error(string message) => new Settings { ["error"] = message };
        if (Cancelled(job)) return Error("Cancelled."); double seconds = (end > start ? end : document.Call("duration").AsDouble()) - start; if (!double.IsFinite(seconds) || seconds <= 0) return Error("There is no timeline audio after the recording start. Move the playhead or select a loop range.");
        double tail = 0; using var effects = new AudioEffectsOperations(); if (end <= start) { tail = effects.tail_seconds(Get(document.Get("master").AsGodotDictionary(), "effects", new GArray()).AsGodotArray()); foreach (var raw in document.Get("tracks").AsGodotArray()) tail += effects.tail_seconds(Get(raw.AsGodotDictionary(), "effects", new GArray()).AsGodotArray()); double clipTail = 0; foreach (var raw in document.Get("actors").AsGodotArray()) clipTail = Math.Max(clipTail, effects.tail_seconds(Get(raw.AsGodotObject().Get("values").AsGodotDictionary(), "effects", new GArray()).AsGodotArray())); tail += clipTail; }
        if (!double.IsFinite(tail) || (seconds + tail) * 44100 * 4 > 512L * 1024 * 1024 - 4096) return Error("This processed recording range exceeds the 512 MiB disk-backing limit (about 50 minutes at stereo 44.1 kHz). Use a shorter loop range.");
        using var crypto = new Crypto(); string directory = ProjectSettings.GlobalizePath("user://audio_workspace/recording_previews/" + Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant()); if (DirAccess.MakeDirRecursiveAbsolute(directory) != Godot.Error.Ok) return Error("Could not create the private recording preparation folder.");
        var backing = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_recording_prepare.gd").Call("_new_backing", directory).As<RefCounted>(); bool retained = false;
        try
        {
            string destination = backing.Get("path").AsString(); var options = new Settings { ["sample_rate"] = 44100, ["bit_depth"] = 16, ["start"] = start, ["include_tail"] = true }; if (end > start) { options["duration"] = end - start; options["include_tail"] = false; } job?.Call("update", 0.0, "Preparing processed timeline for recording"); using var renderer = new AudioRendererOperations(); var rendered = renderer.render(document, destination, options, job); string error = Get(rendered, "error", "").AsString();
            if (Cancelled(job)) error = "Cancelled."; else if (!Get(rendered, "success", false).AsBool()) { if (error.Length == 0) error = "The processed timeline could not be prepared."; }
            else { using var pcm = new AudioPcmFileOperations(); var info = pcm.inspect(destination); backing.Set("info", info); if (Get(info, "error", "invalid").AsString().Length > 0) error = Get(info, "error", "The prepared recording audio is unreadable.").AsString(); else if (Get(info, "file_bytes", 0).AsInt64() > 512L * 1024 * 1024) error = "Effect tails exceeded the 512 MiB disk-backing limit. Use a shorter loop range."; else if (!double.IsFinite(Get(info, "duration", 0.0).AsDouble()) || Get(info, "duration", 0.0).AsDouble() <= 0) error = "The prepared recording audio is empty."; }
            if (error.Length > 0) return Error(error); if (Cancelled(job)) return Error("Cancelled."); retained = true; return new Settings { ["error"] = "", ["backing"] = backing, ["start"] = start };
        }
        finally { if (!retained) release_backing(backing); }
    }
}
