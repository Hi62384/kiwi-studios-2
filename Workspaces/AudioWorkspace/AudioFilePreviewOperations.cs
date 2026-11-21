using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class AudioFilePreviewOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var v) ? v : fallback;
    private static AudioStreamPlayer Player(Node o) => o.Get("player").As<AudioStreamPlayer>();
    private static Settings Info(Node o) => o.Get("info").AsGodotDictionary();
    private static AudioFilePreviewReader? Reader(Node o) => o.Get("_reader").As<AudioFilePreviewReader>();
    private static AudioStreamGeneratorPlayback? Playback(Node o) => o.Get("_playback").As<AudioStreamGeneratorPlayback>();
    private static bool Active(Node o) => o.Get("active").AsBool();
    public string open_file(Node o, string path, string bus, Settings prepared, bool owned, RefCounted? retainedOwner, bool autoStart)
    {
        close_file(o); reap_readers(o, false); o.Set("_last_error", ""); o.Set("_held", !autoStart); var readers = o.Get("_readers").AsGodotArray(); if (readers.Count >= 3) return "Previous PCM readers are still closing. Wait for disk access to finish before opening another preview.";
        using var pcm = new AudioPcmFileOperations(); var info = prepared.Count > 0 ? prepared.Duplicate() : pcm.inspect(path); o.Set("info", info); if (Get(info, "error", "invalid PCM metadata").AsString().Length > 0) return Get(info, "error", "Invalid PCM metadata.").AsString(); if (Get(info, "frames", 0).AsInt64() <= 0 || Get(info, "rate", 0).AsInt64() < 8000) return "The PCM preview metadata has no playable frames.";
        o.Set("duration", info["duration"].AsDouble()); var player = Player(o); player.Stream = new AudioStreamGenerator { MixRate = info["rate"].AsInt32(), BufferLength = .75f }; player.Bus = bus;
        var reader = new AudioFilePreviewReader { path = path, info = info.Duplicate() }; var thread = new GodotThread(); o.Set("_reader", reader);
        if (thread.Start(Callable.From(reader.run)) != Error.Ok) { o.Set("_reader", default(Variant)); player.Stream = null; o.Set("info", new Settings()); o.Set("duration", 0.0); reader.ReleaseWake(); reader.Dispose(); thread.Dispose(); return "The PCM preview worker could not be started."; }
        readers.Add(new Settings { ["reader"] = reader, ["thread"] = thread, ["path"] = path, ["owned"] = owned, ["owner"] = retainedOwner == null ? default(Variant) : Variant.From(retainedOwner) }); o.Set("active", true); seek_file(o, 0); return o.Get("_last_error").AsString();
    }
    public void seek_file(Node o, double seconds)
    {
        var reader = Reader(o); if (!Active(o) || reader == null) return; var player = Player(o); player.Stop(); player.Play(); player.StreamPaused = true; var playback = player.GetStreamPlayback() as AudioStreamGeneratorPlayback; o.Set("_playback", playback == null ? default(Variant) : Variant.From(playback)); if (playback == null) { fail(o, "The native generator playback could not be initialized."); return; }
        o.Set("_capacity", playback.GetFramesAvailable()); var info = Info(o); double requested = seconds * info["rate"].AsDouble(); long origin = (long)Math.Clamp(requested, 0, info["frames"].AsInt64()); o.Set("_origin", origin); o.Set("_pushed", 0L); o.Set("_eof", false); o.Set("_priming", true); o.Set("_primed_at", (long)Time.GetTicksMsec()); o.Set("_generation", reader.seek_to(origin, o.Get("loop_enabled").AsBool()));
    }
    public Settings prepared_token(Node o) { var reader = Reader(o); return reader == null ? new Settings() : new Settings { ["reader"] = Variant.From(GodotObject.WeakRef(reader)), ["generation"] = o.Get("_generation") }; }
    public bool is_primed(Node o, Settings token)
    {
        var reader = Reader(o); if (!Active(o) || reader == null || Playback(o) == null || o.Get("_priming").AsBool()) return false;
        if (token.Count > 0) { if (Get(token, "reader").AsGodotObject() is not WeakRef weak || Get(token, "generation", -1).AsInt64() != o.Get("_generation").AsInt64()) return false; using var reference = weak.GetRef(); if (reference.AsGodotObject() != reader) return false; } return Get(reader.status(), "error", "").AsString().Length == 0;
    }
    public string start_primed(Node o, Settings token) { if (!o.Get("_held").AsBool() || !is_primed(o, token)) return "The prepared PCM buffer is no longer ready. Prepare the take again."; o.Set("_held", false); Player(o).StreamPaused = false; o.Set("_skips", Playback(o)!.GetSkips()); return ""; }
    public double position_seconds(Node o)
    {
        var playback = Playback(o); if (!Active(o) || playback == null) return 0; var info = Info(o); long rate = info["rate"].AsInt64(), origin = o.Get("_origin").AsInt64(); if (o.Get("_held").AsBool()) return (double)origin / rate; long queued = Math.Max(0, o.Get("_capacity").AsInt64() - playback.GetFramesAvailable()), consumed = !o.Get("_priming").AsBool() ? Math.Max(0, o.Get("_pushed").AsInt64() - queued) : 0, frame = origin + consumed; if (o.Get("loop_enabled").AsBool() && info["frames"].AsInt64() > 0) frame %= info["frames"].AsInt64(); return Math.Min(o.Get("duration").AsDouble(), (double)frame / rate);
    }
    public void process(Node o)
    {
        reap_readers(o, false); var reader = Reader(o); var playback = Playback(o); if (!Active(o) || reader == null || playback == null) return; var status = reader.status(); string error = status["error"].AsString(); if (error.Length > 0) { fail(o, error); return; }
        if (!o.Get("_priming").AsBool() && !o.Get("_held").AsBool()) { int skips = playback.GetSkips(); if (skips > o.Get("_skips").AsInt64() && !o.Get("_eof").AsBool()) { fail(o, "File preview underrun: disk/UI did not supply PCM in time. Stop other heavy work and prepare a shorter range."); return; } o.Set("_skips", skips); }
        pump(o); if (!Active(o)) return;
        var info = Info(o); if (o.Get("_priming").AsBool()) { long needed = Math.Min(info["rate"].AsInt64() / 4, o.Get("_capacity").AsInt64()); if (!o.Get("loop_enabled").AsBool()) needed = Math.Min(needed, info["frames"].AsInt64() - o.Get("_origin").AsInt64()); long pushed = o.Get("_pushed").AsInt64(); if (pushed >= needed || (o.Get("_eof").AsBool() && pushed > 0)) { o.Set("_priming", false); Player(o).StreamPaused = o.Get("_held").AsBool(); o.Set("_skips", playback.GetSkips()); } else if ((long)Time.GetTicksMsec() - o.Get("_primed_at").AsInt64() > 5000) { fail(o, "PCM preview could not prepare its bounded playback buffer within five seconds."); return; } }
        if (Active(o) && !o.Get("_held").AsBool() && (o.Get("_eof").AsBool() || (o.Get("_origin").AsInt64() >= info["frames"].AsInt64() && !o.Get("loop_enabled").AsBool())) && o.Get("_capacity").AsInt64() - playback.GetFramesAvailable() <= 0) { close_file(o); o.EmitSignal("finished"); }
    }
    public void pump(Node o)
    {
        for (int burst = 0; burst < 8; ++burst) { var reader = Reader(o); var playback = Playback(o); if (!Active(o) || reader == null || playback == null || o.Get("_eof").AsBool()) return; var packet = reader.TakeNative(playback.GetFramesAvailable()); if (packet == null) return; if (packet.Generation != o.Get("_generation").AsInt64()) continue; if (!playback.PushBuffer(packet.Samples)) { fail(o, "The native generator refused a bounded PCM chunk."); return; } o.Set("_pushed", o.Get("_pushed").AsInt64() + packet.Samples.Length); if (packet.Final) o.Set("_eof", true); }
    }
    public void close_file(Node o) { o.Set("active", false); var player = Player(o); player.Stop(); player.Stream = null; o.Set("_playback", default(Variant)); var reader = Reader(o); if (reader != null) { reader.cancel(); o.Set("_reader", default(Variant)); } o.Set("info", new Settings()); o.Set("duration", 0.0); o.Set("_priming", false); reap_readers(o, false); }
    public void reap_readers(Node o, bool wait)
    {
        var readers = o.Get("_readers").AsGodotArray(); for (int i = readers.Count - 1; i >= 0; --i) { var entry = readers[i].AsGodotDictionary(); var thread = entry["thread"].As<GodotThread>(); if (!wait && thread.IsAlive()) continue; var reader = entry["reader"].As<AudioFilePreviewReader>(); if (reader == Reader(o)) continue; using var result = thread.WaitToFinish(); readers.RemoveAt(i); reader.ReleaseWake(); thread.Dispose(); if (entry["owned"].AsBool()) o.EmitSignal("released", entry["path"].AsString()); }
    }
    public void fail(Node o, string message) { close_file(o); o.Set("_last_error", message); o.EmitSignal("failed", message); }
    public void exit_tree(Node o) { close_file(o); reap_readers(o, true); }
}
