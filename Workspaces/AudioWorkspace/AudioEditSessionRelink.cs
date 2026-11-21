using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioEditSessionOperations
{
    public string audio_source_key(Variant value)
    {
        if (value.VariantType != Variant.Type.String || value.AsString().Length == 0) return "";
        string key = ProjectSettings.GlobalizePath(value.AsString()).Replace('\\', '/').SimplifyPath();
        return OS.GetName() == "Windows" ? key.ToLowerInvariant() : key;
    }
    public Godot.Collections.Array<string> audio_source_clips(RefCounted owner, string id)
    {
        var result = new Godot.Collections.Array<string>();
        var document = Document(owner);
        var actor = document.Call("actor_for_clip", id).AsGodotObject();
        if (actor == null) return result;
        Variant Source(GodotObject item) => item.Get("values").AsGodotDictionary().TryGetValue(new StringName("audio"), out var source) ? source : default;
        string key = audio_source_key(Source(actor));
        if (key.Length == 0) return result;
        foreach (var raw in document.Get("clips").AsGodotArray())
        {
            var clip = raw.AsGodotObject(); var other = document.Call("actor_for_clip", clip.Get("id")).AsGodotObject();
            if (other != null && audio_source_key(Source(other)) == key) result.Add(clip.Get("id").AsString());
        }
        return result;
    }
    public Settings relink_file_signature(string path)
    {
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
        return file == null ? new Settings() : new Settings { ["bytes"] = (long)file.GetLength(), ["modified"] = (long)Godot.FileAccess.GetModifiedTime(path) };
    }
    private static bool SupportedAudio(string path) => path.GetExtension().ToLowerInvariant() is "wav" or "mp3" or "ogg" or "flac";
    public Settings probe_audio_relink(string path, RefCounted? job)
    {
        Settings Error(string message) => new Settings { ["error"] = message };
        bool Cancelled() => job != null && job.Call("is_cancelled").AsBool();
        if (path.Length == 0 || !SupportedAudio(path)) return Error("Choose a supported WAV, MP3, Ogg or FLAC source.");
        if (Cancelled()) return Error("Cancelled.");
        var signature = relink_file_signature(path);
        if (signature.Count == 0 || signature["bytes"].AsInt64() <= 0) return Error("The replacement source is missing, empty or unreadable.");
        var result = new Settings { ["error"] = "", ["path"] = path, ["signature"] = signature, ["seconds"] = 0.0 };
        job?.Call("update", .1, "Checking replacement audio without changing the composition");
        string extension = path.GetExtension().ToLowerInvariant();
        if (extension == "wav")
        {
            using var pcm = new AudioPcmFileOperations();
            var info = pcm.inspect(path);
            if (!info.TryGetValue("error", out var error) || error.AsString().Length > 0) return Error(info.TryGetValue("error", out error) ? error.AsString() : "Unsupported WAV replacement.");
            using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
            if (file == null) return Error("The replacement WAV could not be read.");
            if (pcm.read_frames(file, info, 0, 1).Length != 1 || pcm.read_frames(file, info, info["frames"].AsInt64() - 1, 1).Length != 1) return Error("The replacement WAV is incomplete.");
            result["seconds"] = info["duration"];
        }
        else
        {
            if ((extension is "mp3" or "ogg") && signature["bytes"].AsInt64() > 64L * 1024 * 1024) return Error("Compressed replacement validation is limited to 64 MiB encoded files. Convert this source to PCM WAV before relinking.");
            var audio = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs");
            audio.Call("invalidate", path);
            if (audio.Call("needs_file_preview", path).AsBool()) return Error("This compressed source exceeds the native validation limit. Convert it to PCM WAV before relinking; existing clips were preserved.");
            var stream = audio.Call("source", path, job == null ? default(Variant) : Variant.From(job)).As<AudioStream>();
            if (stream == null) return Error("The replacement cannot be decoded by the current audio backend.");
            result["seconds"] = stream.GetLength();
            using var decoder = stream.InstantiatePlayback();
            if (decoder == null) return Error("The replacement decoder could not be initialized.");
            decoder.Start(0);
            Vector2[] samples;
            try { samples = decoder.MixAudio(1, 32); } finally { decoder.Stop(); }
            if (samples.Length == 0) return Error("The replacement decoder returned no audio frames.");
            result["stream"] = stream;
        }
        double seconds = result["seconds"].AsDouble();
        if (!double.IsFinite(seconds) || seconds <= 0) return Error("The replacement has no valid audio duration.");
        if (Cancelled()) return Error("Cancelled.");
        if (!signature.RecursiveEqual(relink_file_signature(path))) return Error("The replacement file changed while being checked. Choose it again.");
        return result;
    }
    public string audio_relink_problem(RefCounted owner, GArray ids, string expectedSource, Settings replacement)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return "Finish the current edit before relinking audio.";
        if (ids.Count == 0) return "No clips were selected for relinking.";
        string key = audio_source_key(expectedSource);
        if (key.Length == 0) return "Only existing file-backed clip references can be relinked.";
        if (replacement.TryGetValue("error", out var error) && error.AsString().Length > 0) return error.AsString();
        if (!replacement.TryGetValue("path", out var pathRaw) || pathRaw.VariantType != Variant.Type.String || pathRaw.AsString().Length == 0 || !SupportedAudio(pathRaw.AsString()) || !replacement.TryGetValue("seconds", out var secondsRaw) || secondsRaw.VariantType is not Variant.Type.Float and not Variant.Type.Int) return "The replacement audio has not been validated.";
        string path = pathRaw.AsString(); double seconds = secondsRaw.AsDouble();
        if (!double.IsFinite(seconds) || seconds <= 0) return "The replacement has no valid duration.";
        if (!replacement.TryGetValue("signature", out var signature) || signature.VariantType != Variant.Type.Dictionary || signature.AsGodotDictionary().Count == 0 || !signature.AsGodotDictionary().RecursiveEqual(relink_file_signature(path))) return "The replacement file is missing or changed. Choose it again.";
        if (path.GetExtension().ToLowerInvariant() == "wav")
        {
            using var pcm = new AudioPcmFileOperations(); var info = pcm.inspect(path);
            if (!info.TryGetValue("error", out error) || error.AsString().Length > 0 || !info.TryGetValue("duration", out var duration) || Math.Abs(duration.AsDouble() - seconds) > .000001) return "The replacement WAV no longer matches its validation. Choose it again.";
        }
        else if (!replacement.TryGetValue("stream", out var streamRaw) || streamRaw.VariantType != Variant.Type.Object || streamRaw.AsGodotObject() is not AudioStream stream || Math.Abs(stream.GetLength() - seconds) > .000001) return "The replacement decoder is unavailable. Choose the source again.";
        var seen = new System.Collections.Generic.HashSet<string>(); var document = Document(owner);
        foreach (var raw in ids)
        {
            if (raw.VariantType != Variant.Type.String || raw.AsString().Length == 0 || !seen.Add(raw.AsString())) return "The relink selection contains an invalid or duplicate clip.";
            string id = raw.AsString();
            var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject(); var track = document.Call("track_for_clip", id).AsGodotDictionary();
            if (clip == null || actor == null || track.Count == 0) return "A clip selected for relinking is missing. No clips were changed.";
            if (!can_edit(owner, id) || track.ContainsKey("frozen_track") || track.ContainsKey("frozen_source")) return "A selected clip is locked or frozen. No clips were changed.";
            var values = actor.Get("values").AsGodotDictionary();
            if (!values.TryGetValue(new StringName("audio"), out var audio) || audio_source_key(audio) != key) return "A selected clip's source changed. Choose the replacement again.";
            if (is_note_source(actor)) return "Generated note sources cannot be relinked as audio. Restore their instrument samples or render them separately.";
            double start = clip.Get("start_time").AsDouble(), offset = clip.Get("source_offset").AsDouble(), duration = clip.Get("duration").AsDouble(), speed = clip.Get("playback_speed").AsDouble();
            if (!double.IsFinite(start) || start < 0 || !double.IsFinite(offset) || offset < 0 || !double.IsFinite(duration) || duration <= 0 || !double.IsFinite(speed) || speed < .05 || speed > 16) return "A selected clip has invalid source geometry. No clips were changed.";
            if (values.TryGetValue(new StringName("loop"), out var loop) && loop.AsBool())
            {
                double period = values.TryGetValue(new StringName("source_duration"), out var length) ? length.AsDouble() : 0;
                if (!double.IsFinite(period) || period <= 0 || Math.Abs(period - seconds) > .000001) return "A looped clip requires the original source duration to preserve its loop period. No clips were changed.";
            }
            else { double end = offset + duration * speed; if (!double.IsFinite(end) || end > seconds + .000001) return "The replacement is too short for an existing source window. No clips were changed."; }
        }
        return "";
    }
    public string relink_audio_sources(RefCounted owner, GArray ids, string expectedSource, Settings replacement)
    {
        string problem = audio_relink_problem(owner, ids, expectedSource, replacement);
        if (problem.Length > 0) return problem;
        var changes = new System.Collections.Generic.List<GodotObject>(); var document = Document(owner);
        foreach (var id in ids)
        {
            var actor = document.Call("actor_for_clip", id).AsGodotObject(); var values = actor.Get("values").AsGodotDictionary();
            if (!values.TryGetValue(new StringName("audio"), out var source) || source.AsString() != replacement["path"].AsString() || !values.TryGetValue(new StringName("source_duration"), out var seconds) || seconds.AsDouble() != replacement["seconds"].AsDouble() || values.ContainsKey(new StringName("transients")) || values.ContainsKey(new StringName("transients_source_identity"))) changes.Add(actor);
        }
        GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("invalidate", replacement["path"]);
        if (changes.Count == 0) return "";
        begin(owner, "Relink audio sources");
        foreach (var actor in changes)
        {
            var values = actor.Get("values").AsGodotDictionary(); values[new StringName("audio")] = replacement["path"]; values[new StringName("source_duration")] = replacement["seconds"].AsDouble();
            values.Remove(new StringName("transients")); values.Remove(new StringName("transients_source_identity"));
        }
        commit(owner); return "";
    }
}
