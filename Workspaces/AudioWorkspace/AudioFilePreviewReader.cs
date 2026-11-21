using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class AudioFilePreviewReader : RefCounted
{
    private readonly object _gate = new();
    private readonly System.Threading.AutoResetEvent _wake = new(false);
    private readonly System.Collections.Generic.Queue<Packet> _chunks = new();
    public string path { get; set; } = "";
    public Settings info { get; set; } = new();
    public bool pending_wake, cancelled, looped, done;
    public long generation, first;
    public string error = "";
    internal sealed record Packet(Vector2[] Samples, long Generation, bool Final);
    private void Notify() { if (!pending_wake) { pending_wake = true; _wake.Set(); } }
    public long seek_to(long frame, bool loop) { lock (_gate) { ++generation; first = frame; looped = loop; _chunks.Clear(); done = false; Notify(); return generation; } }
    public void cancel() { lock (_gate) { cancelled = true; _chunks.Clear(); Notify(); } }
    internal Packet? TakeNative(int frames) { lock (_gate) { if (_chunks.Count == 0 || _chunks.Peek().Samples.Length > frames) return null; var packet = _chunks.Dequeue(); Notify(); return packet; } }
    public Settings take(int frames) { var packet = TakeNative(frames); return packet == null ? new Settings() : new Settings { ["samples"] = packet.Samples, ["generation"] = packet.Generation, ["final"] = packet.Final }; }
    public Settings status() { lock (_gate) return new Settings { ["error"] = error, ["done"] = done, ["queued"] = _chunks.Count }; }
    public void set_error(string message) { lock (_gate) if (!cancelled) error = message; }
    public void run()
    {
        try
        {
            using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read); if (file == null) { set_error("The file preview source could not be opened."); return; }
            bool Changed() => (long)file.GetLength() != info["file_bytes"].AsInt64() || (long)Godot.FileAccess.GetModifiedTime(path) != info["modified"].AsInt64();
            if (Changed()) { set_error("The PCM source changed before playback. Prepare it again."); return; }
            long cursor = 0, current = -1; ulong checkedAt = Time.GetTicksMsec(); using var pcm = new AudioPcmFileOperations();
            while (true)
            {
                bool stop, wait, looping;
                lock (_gate) { stop = cancelled; if (current != generation) { current = generation; cursor = first; } wait = done || _chunks.Count >= 32; looping = looped; }
                if (stop) break;
                if (wait) { _wake.WaitOne(); lock (_gate) pending_wake = false; continue; }
                if (Time.GetTicksMsec() - checkedAt >= 1000) { checkedAt = Time.GetTicksMsec(); if (Changed()) { set_error("File preview stopped because its PCM source changed."); break; } }
                long frames = info["frames"].AsInt64(); if (cursor >= frames) { if (looping) cursor = 0; else { lock (_gate) if (current == generation) done = true; continue; } }
                int count = (int)Math.Min(2048, frames - cursor); var samples = pcm.read_frames(file, info, cursor, count); if (samples.Length != count) { set_error("The PCM preview file ended before its declared data boundary."); break; } cursor += count; bool final = cursor >= frames && !looping;
                lock (_gate) if (current == generation && !cancelled) { _chunks.Enqueue(new Packet(samples, current, final)); if (final) done = true; }
            }
        }
        catch (Exception failure) { set_error("The PCM preview reader stopped: " + failure.Message); }
    }
    internal void ReleaseWake() => _wake.Dispose();
}
