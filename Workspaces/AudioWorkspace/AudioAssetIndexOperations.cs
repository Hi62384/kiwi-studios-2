using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioAssetIndexOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var v) ? v : fallback;
    private static bool AudioPath(string path) => path.GetExtension().ToLowerInvariant() is "wav" or "mp3" or "ogg" or "flac";
    private static bool Cancelled(RefCounted work) => work is AudioWorkToken token ? token.is_cancelled() : work.Call("is_cancelled").AsBool();
    public long request(Node o, GArray roots, GArray previous) { long generation = o.Get("_generation").AsInt64() + 1; o.Set("_generation", generation); o.Get("_work").AsGodotObject()?.Call("cancel"); o.Set("_pending", new Settings { ["roots"] = roots.Duplicate(), ["previous"] = previous.Duplicate(true), ["generation"] = generation }); return generation; }
    public void cancel(Node o) { o.Set("_generation", o.Get("_generation").AsInt64() + 1); o.Get("_pending").AsGodotDictionary().Clear(); o.Get("_work").AsGodotObject()?.Call("cancel"); }
    public bool busy(Node o) => o.Get("_thread").AsGodotObject() != null || o.Get("_pending").AsGodotDictionary().Count > 0;
    public void process(Node o, double delta)
    {
        var thread = o.Get("_thread").As<GodotThread>();
        if (thread != null)
        {
            double elapsed = o.Get("_progress_elapsed").AsDouble() + delta; o.Set("_progress_elapsed", elapsed); var work = o.Get("_work").As<RefCounted>();
            if (elapsed >= .15 && o.Get("_running_generation").AsInt64() == o.Get("_generation").AsInt64()) { o.Set("_progress_elapsed", 0.0); var status = work.Call("status").AsGodotDictionary(); o.EmitSignal("progress_changed", status["description"].AsString()); }
            if (thread.IsAlive()) return; using var result = thread.WaitToFinish(); bool accept = o.Get("_running_generation").AsInt64() == o.Get("_generation").AsInt64() && !Cancelled(work); o.Set("_thread", default(Variant)); o.Set("_work", default(Variant)); thread.Dispose(); if (accept) o.EmitSignal("scan_finished", o.Get("_running_generation"), result);
        }
        var pending = o.Get("_pending").AsGodotDictionary();
        if (o.Get("_thread").AsGodotObject() == null && pending.Count > 0)
        {
            o.Set("_pending", new Settings()); o.Set("_running_generation", pending["generation"]); var work = new AudioWorkToken(); thread = new GodotThread(); o.Set("_work", work); o.Set("_thread", thread); var roots = pending["roots"].AsGodotArray(); var previous = pending["previous"].AsGodotArray();
            if (thread.Start(Callable.From(() => scan(roots, previous, work))) != Error.Ok) { o.Set("_thread", default(Variant)); o.Set("_work", default(Variant)); thread.Dispose(); work.Dispose(); o.EmitSignal("scan_finished", o.Get("_running_generation"), new Settings { ["error"] = "Could not start the project audio index worker." }); }
        }
    }
    public void exit_tree(Node o) { cancel(o); var thread = o.Get("_thread").As<GodotThread>(); if (thread != null) { using var result = thread.WaitToFinish(); thread.Dispose(); } o.Set("_thread", default(Variant)); o.Set("_work", default(Variant)); }
    public string canonical_root(string value)
    {
        if (!value.StartsWith("res://", StringComparison.Ordinal) || value.Length > 1024 || value.Contains('\\')) return ""; string relative = value[6..]; if (relative.EndsWith('/')) relative = relative[..^1]; if (relative.Length == 0) return "res://";
        foreach (string part in relative.Split('/')) if (part.Length == 0 || part is "." or ".." || part.ToLowerInvariant() is ".godot" or ".git" || part.Contains(':')) return ""; return "res://" + relative;
    }
    public bool contains_path(string root, string path) => root == "res://" ? path.StartsWith("res://", StringComparison.Ordinal) : path == root || path.StartsWith(root + "/", StringComparison.Ordinal);
    public string path_state(string path, bool directory)
    {
        string clean = canonical_root(path); if (clean.Length == 0 || clean != path) return "blocked"; DirAccess? access = DirAccess.Open("res://"); if (access == null) return "unreadable";
        try { if (path == "res://") return directory ? "available" : "blocked"; string[] parts = path[6..].Split('/'); string at = "res://"; for (int i = 0; i < parts.Length; ++i) { string part = parts[i]; if (access.IsLink(part)) return "blocked"; if (i < parts.Length - 1 || directory) { if (!access.DirExists(part)) return "missing"; at = at.PathJoin(part); var next = DirAccess.Open(at); access.Dispose(); access = next; if (access == null) return "unreadable"; } else if (!access.FileExists(part)) return "missing"; } return "available"; }
        finally { access?.Dispose(); }
    }
    public bool usable(Settings entry) { string source = Get(entry, "source", "").AsString(), root = canonical_root(Get(entry, "index_root", "").AsString()); if (root.Length == 0 || !contains_path(root, source) || !AudioPath(source) || Get(entry, "asset_state", "unverified").AsString() != "available" || path_state(source, false) != "available") return false; using var file = Godot.FileAccess.Open(source, Godot.FileAccess.ModeFlags.Read); return file != null; }
    public string root_for(string path, GArray roots) { foreach (var root in roots) if (contains_path(root.AsString(), path)) return root.AsString(); return ""; }
    public Settings blank(string path, string root) => new Settings { ["id"] = "asset_" + path.Sha256Text(), ["label"] = path.GetFile(), ["kind"] = "asset", ["category"] = "Project", ["origin"] = "project", ["source"] = path, ["project_indexed"] = true, ["index_root"] = root, ["asset_state"] = "unverified", ["metadata_note"] = "Metadata not checked in this scan." };
    public string describe(Settings entry) { string message = Get(entry, "asset_state", "unverified").AsString() switch { "missing" => "Missing file or containing folder.", "unreadable" => "The file or folder could not be read.", "blocked" => "Outside the allowed project scope, excluded, or a symbolic link.", "unverified" => "Not checked in the latest scan; refresh or choose a smaller folder.", _ => "Readable; playback has not been checked." }; return Get(entry, "source", "").AsString() + "\n" + message + "\n" + Get(entry, "metadata_note", "Duration not indexed.").AsString(); }
    public Settings scan(GArray requested, GArray previous, RefCounted work)
    {
        ulong began = Time.GetTicksMsec(); var roots = new GArray(); foreach (var raw in requested) { string root = canonical_root(raw.AsString()); if (root.Length > 0 && !roots.Contains(root) && roots.Count < 8) roots.Add(root); }
        var records = new Settings(); foreach (var raw in previous) { if (records.Count >= 2048) break; string path = Get(raw.AsGodotDictionary(), "source", "").AsString(), root = root_for(path, roots); if (root.Length == 0 || canonical_root(path) != path) continue; records[path] = blank(path, root); }
        var queue = new System.Collections.Generic.List<(string Path, string Root, int Depth)>(); foreach (var root in roots) queue.Add((root.AsString(), root.AsString(), 0)); int cursor = 0, visited = 0, inspected = 0, skippedLinks = 0, unreadableFolders = 0, headerBytes = 0; string limit = ""; var observed = new System.Collections.Generic.HashSet<string>();
        while (cursor < queue.Count)
        {
            if (Cancelled(work)) return new Settings { ["cancelled"] = true }; if (Time.GetTicksMsec() - began >= 15000) { limit = "15-second scan budget reached."; break; } var folder = queue[cursor++]; if (path_state(folder.Path, true) != "available") { ++unreadableFolders; continue; }
            using var directory = DirAccess.Open(folder.Path); if (directory == null) { ++unreadableFolders; continue; } directory.IncludeHidden = true; directory.IncludeNavigational = false; if (directory.ListDirBegin() != Error.Ok) { ++unreadableFolders; continue; }
            string name = directory.GetNext();
            try
            {
                while (name.Length > 0)
                {
                    if (Cancelled(work)) return new Settings { ["cancelled"] = true }; if (visited >= 20000 || Time.GetTicksMsec() - began >= 15000) { limit = visited >= 20000 ? "20,000-entry scan budget reached." : "15-second scan budget reached."; break; } ++visited; string path = folder.Path.PathJoin(name);
                    if (name.ToLowerInvariant() is ".godot" or ".git" || canonical_root(path).Length == 0) { name = directory.GetNext(); continue; }
                    if (directory.IsLink(name)) ++skippedLinks;
                    else if (directory.CurrentIsDir()) { if (folder.Depth >= 16 || queue.Count >= 512) limit = "Folder/depth limit reached; choose a smaller project folder."; else queue.Add((path, folder.Root, folder.Depth + 1)); }
                    else if (AudioPath(path))
                    {
                        if (!records.ContainsKey(path) && records.Count >= 2048) { limit = "2,048-asset limit reached; choose a smaller project folder."; break; } if (headerBytes >= 16 * 1024 * 1024) { limit = "16 MiB metadata-read budget reached; choose a smaller project folder."; break; }
                        var entry = inspect(path, folder.Root, Math.Min(65536, 16 * 1024 * 1024 - headerBytes)); headerBytes += Get(entry, "header_bytes", 0).AsInt32(); entry.Remove("header_bytes"); records[path] = entry; observed.Add(path); ++inspected; string message = "Indexing: " + inspected + " audio files · " + cursor + " folders"; if (work is AudioWorkToken token) token.update(inspected / 2048.0, message); else work.Call("update", inspected / 2048.0, message);
                    }
                    name = directory.GetNext();
                }
            }
            finally { directory.ListDirEnd(); }
            if (name.Length > 0) break;
        }
        foreach (var key in records.Keys)
        {
            if (Cancelled(work)) return new Settings { ["cancelled"] = true }; string path = key.AsString(); if (observed.Contains(path)) continue; if (Time.GetTicksMsec() - began >= 15000) { if (limit.Length == 0) limit = "15-second scan budget reached."; break; } string state = path_state(path, false); if (state == "available") { using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read); state = file != null ? "unverified" : "unreadable"; } records[key].AsGodotDictionary()["asset_state"] = state;
        }
        var entries = new Godot.Collections.Array<Settings>(); foreach (var raw in records.Values) { var entry = raw.AsGodotDictionary(); entry["description"] = describe(entry); entries.Add(entry); }
        return new Settings { ["entries"] = entries, ["partial"] = limit.Length > 0 || unreadableFolders > 0, ["limit_reason"] = limit, ["inspected"] = inspected, ["folders"] = cursor, ["visited"] = visited, ["skipped_links"] = skippedLinks, ["unreadable_folders"] = unreadableFolders, ["header_bytes"] = headerBytes, ["elapsed_msec"] = (long)(Time.GetTicksMsec() - began) };
    }
    public Settings inspect(string path, string root, int budget)
    {
        var entry = blank(path, root); string state = path_state(path, false); entry["asset_state"] = state; if (state != "available") return entry; byte[] bytes; long size;
        using (var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read)) { if (file == null) { entry["asset_state"] = "unreadable"; return entry; } size = (long)file.GetLength(); entry["size_bytes"] = size; entry["modified_time"] = (long)Godot.FileAccess.GetModifiedTime(path); int expected = (int)Math.Min(size, Math.Min(budget, path.GetExtension().ToLowerInvariant() == "wav" ? 65536 : 4096)); bytes = file.GetBuffer(expected); entry["header_bytes"] = bytes.Length; if (bytes.Length != expected) { entry["asset_state"] = "unreadable"; entry["metadata_note"] = "The metadata header could not be fully read."; return entry; } }
        entry["metadata_note"] = "Duration not indexed; playback/decoder support is checked only when used."; switch (path.GetExtension().ToLowerInvariant()) { case "wav": wav_metadata(bytes, size, entry); break; case "flac": flac_metadata(bytes, entry); break; case "mp3": case "ogg": entry["metadata_note"] = "Compressed duration is unknown until loaded; the index does not decode audio."; break; } return entry;
    }
    public bool tag(byte[] bytes, int at, string value) { if (at < 0 || (long)at + value.Length > bytes.Length) return false; for (int i = 0; i < value.Length; ++i) if (bytes[at + i] != value[i]) return false; return true; }
    public void wav_metadata(byte[] bytes, long size, Settings entry)
    {
        if (bytes.Length < 12 || !tag(bytes, 0, "RIFF") || !tag(bytes, 8, "WAVE")) { entry["metadata_note"] = "Unrecognized WAV header; playback has not been checked."; return; }
        long rate = 0, channels = 0, align = 0, byteRate = 0, dataBytes = -1; int at = 12; bool pcm = false;
        while (at + 8 <= bytes.Length)
        {
            long length = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(at + 4, 4)); int start = at + 8;
            if (tag(bytes, at, "fmt ") && length >= 16 && start + 16 <= bytes.Length) { int format = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(start, 2)); channels = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(start + 2, 2)); rate = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(start + 4, 4)); byteRate = System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(start + 8, 4)); align = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(start + 12, 2)); int bits = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(start + 14, 2)); pcm = format is 1 or 3 && channels > 0 && channels <= 64 && bits is 8 or 16 or 24 or 32 or 64 && align == channels * (bits / 8) && byteRate == rate * align; }
            else if (tag(bytes, at, "data")) { if (start + length <= size) dataBytes = length; break; }
            if (start + length > bytes.Length) break; at = (int)(start + length + length % 2);
        }
        if (rate > 0) entry["sample_rate"] = rate; if (channels > 0) entry["channels"] = channels;
        if (pcm && rate > 0 && byteRate > 0 && dataBytes >= 0 && dataBytes % align == 0) { entry["duration"] = (double)dataBytes / byteRate; entry["duration_estimated"] = true; entry["metadata_note"] = "Header-derived duration estimate (PCM/float WAV); samples have not been decoded."; } else entry["metadata_note"] = "WAV duration is unknown within the 64 KiB header limit or this encoding; playback is unchecked.";
    }
    public void flac_metadata(byte[] bytes, Settings entry)
    {
        if (bytes.Length < 42 || !tag(bytes, 0, "fLaC") || (bytes[4] & 127) != 0 || bytes[5] != 0 || bytes[6] != 0 || bytes[7] != 34) { entry["metadata_note"] = "FLAC STREAMINFO is unavailable in the bounded header. Preview may require the existing FFmpeg loader."; return; }
        int rate = (bytes[18] << 12) | (bytes[19] << 4) | (bytes[20] >> 4), channels = ((bytes[20] >> 1) & 7) + 1; long samples = ((long)(bytes[21] & 15) << 32) | ((long)bytes[22] << 24) | ((long)bytes[23] << 16) | ((long)bytes[24] << 8) | bytes[25]; entry["sample_rate"] = rate; entry["channels"] = channels; if (rate > 0 && samples > 0) { entry["duration"] = (double)samples / rate; entry["duration_estimated"] = true; entry["metadata_note"] = "Header-derived FLAC duration estimate; decode unchecked. Preview may require the existing FFmpeg loader."; }
    }
}
