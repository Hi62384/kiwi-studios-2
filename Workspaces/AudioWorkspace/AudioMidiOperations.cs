using Godot;
using System;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioMidiOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var v) ? v : fallback;
    private static Settings Failure(string message) => new Settings { ["error"] = message, ["parts"] = new GArray(), ["tempos"] = new GArray(), ["time_signatures"] = new GArray(), ["warnings"] = new GArray() };
    private sealed class Reader
    {
        public readonly byte[] Data; public int Position; public readonly int End; public string Error = "";
        public Reader(byte[] data, int start = 0, int end = -1) { Data = data; Position = start; End = end < 0 ? data.Length : Math.Min(end, data.Length); }
        public int Byte() { if (Position >= End) { Error = "Truncated MIDI event."; return 0; } return Data[Position++]; }
        public int Be16() => (Byte() << 8) | Byte();
        public long Be32() => ((long)Byte() << 24) | ((long)Byte() << 16) | ((long)Byte() << 8) | (long)Byte();
        public byte[] Block(int count) { if (count < 0 || count > End - Position) { Error = "MIDI chunk extends beyond the file."; return Array.Empty<byte>(); } var result = Data.AsSpan(Position, count).ToArray(); Position += count; return result; }
        public int Variable() { int value = 0; for (int i = 0; i < 4; ++i) { int b = Byte(); if (Error.Length > 0) return 0; value = (value << 7) | (b & 127); if (b < 128) return value; } Error = "Invalid MIDI variable-length integer."; return 0; }
    }
    public Settings read(string path)
    {
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read); if (file == null) return Failure("Could not open MIDI file.");
        if (file.GetLength() > 32L * 1024 * 1024) return Failure("MIDI file exceeds the 32 MiB safety limit."); return read_bytes(file.GetBuffer((long)file.GetLength()));
    }
    public string program_instrument(int program) => program < 8 ? "piano" : program < 16 ? "bells" : program < 24 ? "organ" : program < 32 ? "pluck" : program < 40 ? "bass" : program < 56 ? "strings" : program < 64 ? "brass" : program < 88 ? "lead" : program < 104 ? "pad" : program < 112 ? "pluck" : program < 120 ? "drums" : "cinematic";
    public Settings read_bytes(byte[] bytes)
    {
        if (bytes.Length < 14 || bytes.Length > 32 * 1024 * 1024) return Failure("Invalid MIDI file size."); var cursor = new Reader(bytes);
        string Ascii(byte[] value) => System.Text.Encoding.ASCII.GetString(value);
        if (Ascii(cursor.Block(4)) != "MThd") return Failure("Missing MIDI header."); long headerLength = cursor.Be32(); if (headerLength < 6 || headerLength > bytes.Length - 8) return Failure("Invalid MIDI header length.");
        int format = cursor.Be16(), trackCount = cursor.Be16(), division = cursor.Be16();
        if (format is not 0 and not 1) return Failure("Only MIDI type 0 and type 1 are supported; type 2 sequences must be imported separately.");
        if ((division & 0x8000) != 0) return Failure("SMPTE-timed MIDI is not supported; convert to quarter-note PPQ timing.");
        if (division <= 0 || trackCount < 1 || trackCount > 1024) return Failure("Invalid MIDI timing or track count."); if (format == 0 && trackCount != 1) return Failure("MIDI type 0 must contain exactly one track.");
        cursor.Position = 8 + (int)headerLength; var parts = new GArray(); var tempos = new List<Settings>(); var signatures = new List<Settings>(); var warnings = new Godot.Collections.Array<string>(); long durationTicks = 0; int eventCount = 0, noteCount = 0;
        void Warn(string message) { if (!warnings.Contains(message)) warnings.Add(message); }
        for (int trackIndex = 0; trackIndex < trackCount; ++trackIndex)
        {
            if (cursor.Position + 8 > bytes.Length) return Failure("Missing MIDI track chunk."); string chunk = Ascii(cursor.Block(4)); long chunkLength = cursor.Be32(); if (chunk != "MTrk") return Failure("Expected a MIDI track chunk."); if (chunkLength > bytes.Length - cursor.Position) return Failure("Truncated MIDI track chunk.");
            var track = new Reader(bytes, cursor.Position, cursor.Position + (int)chunkLength); cursor.Position += (int)chunkLength;
            long ticks = 0; int running = -1; var active = new Dictionary<string, Queue<Settings>>(); var channelParts = new Dictionary<int, Settings>(); var channelPan = new Dictionary<int, double>(); string trackName = "Track " + (trackIndex + 1);
            void Finish(string key, Settings part, double beat) { if (!active.TryGetValue(key, out var queue) || queue.Count == 0) return; var note = queue.Dequeue(); note["duration"] = Math.Max(0, beat - note["start"].AsDouble()); part["notes"].AsGodotArray().Add(note); }
            while (track.Position < track.End && track.Error.Length == 0)
            {
                if (++eventCount > 1000000) return Failure("MIDI event limit exceeded."); ticks += track.Variable(); durationTicks = Math.Max(durationTicks, ticks); int status = track.Byte();
                if (status < 0x80) { if (running < 0) return Failure("MIDI running status has no preceding channel event."); --track.Position; status = running; } else if (status < 0xf0) running = status;
                if (status == 0xff)
                {
                    running = -1; int metaType = track.Byte(), metaLength = track.Variable(); var payload = track.Block(metaLength); if (track.Error.Length > 0) break;
                    if (metaType == 0x2f) break;
                    if (metaType == 3) trackName = System.Text.Encoding.UTF8.GetString(payload);
                    else if (metaType == 0x51 && payload.Length == 3) { if (tempos.Count >= 4096) return Failure("MIDI tempo maps are limited to 4096 events."); int microseconds = (payload[0] << 16) | (payload[1] << 8) | payload[2]; if (microseconds > 0) tempos.Add(new Settings { ["beat"] = (double)ticks / division, ["bpm"] = 60000000.0 / microseconds, ["microseconds"] = microseconds, ["order"] = eventCount }); }
                    else if (metaType == 0x58 && payload.Length >= 4 && payload[1] <= 7) { if (signatures.Count >= 4096) return Failure("MIDI meter maps are limited to 4096 events."); signatures.Add(new Settings { ["beat"] = (double)ticks / division, ["numerator"] = (int)payload[0], ["denominator"] = 1 << payload[1], ["clocks_per_click"] = (int)payload[2], ["thirty_seconds"] = (int)payload[3], ["order"] = eventCount }); }
                    continue;
                }
                if (status is 0xf0 or 0xf7) { running = -1; track.Block(track.Variable()); Warn("System-exclusive events are not retained."); continue; }
                if (status >= 0xf0) return Failure("Unsupported system event in MIDI track."); int type = status & 0xf0, channel = status & 15, first = track.Byte(), second = type is 0xc0 or 0xd0 ? 0 : track.Byte();
                if (first >= 128 || second >= 128) return Failure("Invalid MIDI channel event data.");
                if (!channelParts.TryGetValue(channel, out var part)) { if (parts.Count + channelParts.Count >= 128) return Failure("A MIDI import is limited to 128 track/channel sources."); part = new Settings { ["id"] = "midi_" + trackIndex + "_" + channel, ["role"] = channel == 9 ? "drums" : "instrument", ["label"] = trackName, ["instrument"] = new Settings { ["id"] = channel == 9 ? "drums" : "piano", ["midi_program"] = 0, ["midi_channel"] = channel }, ["notes"] = new GArray(), ["events"] = new GArray() }; channelParts[channel] = part; }
                double beat = (double)ticks / division; string noteKey = channel + ":" + first; var events = part["events"].AsGodotArray();
                switch (type)
                {
                    case 0x90:
                        if (second > 0) { if (++noteCount > 65536) return Failure("A MIDI import is limited to 65536 notes in total."); if (!active.TryGetValue(noteKey, out var queue)) { queue = new Queue<Settings>(); active[noteKey] = queue; } queue.Enqueue(new Settings { ["id"] = (trackIndex + ":" + channel + ":" + first + ":" + ticks + ":" + eventCount).Sha256Text()[..32], ["pitch"] = first, ["start"] = beat, ["duration"] = 0.0, ["velocity"] = second / 127.0, ["pan"] = channelPan.TryGetValue(channel, out var pan) ? pan : 0 }); } else Finish(noteKey, part, beat); break;
                    case 0x80: Finish(noteKey, part, beat); break;
                    case 0xb0: events.Add(new Settings { ["beat"] = beat, ["type"] = "control_change", ["controller"] = first, ["value"] = second }); if (first == 10) channelPan[channel] = Math.Clamp((second - 64.0) / 63, -1, 1); break;
                    case 0xc0: events.Add(new Settings { ["beat"] = beat, ["type"] = "program_change", ["program"] = first }); if (beat == 0) { var instrument = part["instrument"].AsGodotDictionary(); instrument["midi_program"] = first; if (channel != 9) instrument["id"] = program_instrument(first); } break;
                    case 0xe0: events.Add(new Settings { ["beat"] = beat, ["type"] = "pitch_bend", ["value"] = (second << 7) | first }); break;
                    case 0xa0: events.Add(new Settings { ["beat"] = beat, ["type"] = "poly_pressure", ["pitch"] = first, ["value"] = second }); break;
                    case 0xd0: events.Add(new Settings { ["beat"] = beat, ["type"] = "channel_pressure", ["value"] = first }); break;
                }
                if (events.Count > 16384) return Failure("A MIDI source is limited to 16384 channel events.");
            }
            if (track.Error.Length > 0) return Failure(track.Error);
            foreach (var pair in active) { int channel = int.Parse(pair.Key.Split(':')[0], System.Globalization.CultureInfo.InvariantCulture); var part = channelParts[channel]; foreach (var note in pair.Value) { note["duration"] = Math.Max(1.0 / division, (double)ticks / division - note["start"].AsDouble()); part["notes"].AsGodotArray().Add(note); } if (pair.Value.Count > 0) Warn("Unclosed notes were ended at the track boundary."); }
            foreach (var pair in channelParts)
            {
                var part = pair.Value; var notes = part["notes"].AsGodotArray(); if (notes.Count > 8192) return Failure("A MIDI source is limited to 8192 notes."); part["duration"] = (double)ticks / division; part["label"] = trackName + (channelParts.Count > 1 ? " (channel " + (pair.Key + 1) + ")" : ""); var ordered = new List<Variant>(); foreach (var note in notes) ordered.Add(note); ordered.Sort((a, b) => a.AsGodotDictionary()["start"].AsDouble().CompareTo(b.AsGodotDictionary()["start"].AsDouble())); notes.Clear(); foreach (var note in ordered) notes.Add(note); parts.Add(part);
            }
        }
        Settings DefaultTempo() => new Settings { ["beat"] = 0.0, ["bpm"] = 120.0, ["microseconds"] = 500000 };
        Settings DefaultMeter() => new Settings { ["beat"] = 0.0, ["numerator"] = 4, ["denominator"] = 4, ["clocks_per_click"] = 24, ["thirty_seconds"] = 8 };
        if (tempos.Count == 0) tempos.Add(DefaultTempo()); if (signatures.Count == 0) signatures.Add(DefaultMeter());
        int Compare(Settings a, Settings b) { int beat = a["beat"].AsDouble().CompareTo(b["beat"].AsDouble()); return beat != 0 ? beat : Get(a, "order", 0).AsInt32().CompareTo(Get(b, "order", 0).AsInt32()); }
        tempos.Sort(Compare); signatures.Sort(Compare); foreach (var item in tempos) item.Remove("order"); foreach (var item in signatures) item.Remove("order"); if (tempos[0]["beat"].AsDouble() > 0) tempos.Insert(0, DefaultTempo()); if (signatures[0]["beat"].AsDouble() > 0) signatures.Insert(0, DefaultMeter());
        var tempoArray = new GArray(); foreach (var item in tempos) tempoArray.Add(item); var meterArray = new GArray(); foreach (var item in signatures) meterArray.Add(item);
        using var maps = new AudioTempoMapOperations(); string error = maps.validate_tempos(tempoArray, true); if (error.Length == 0) error = maps.validate_meters(meterArray); if (error.Length > 0) return Failure(error);
        if ((parts.Count + 1L) * (tempos.Count + signatures.Count) > 65536) return Failure("This import would exceed 65536 copied tempo/meter events. Reduce tracks or conductor events before importing.");
        int channelEvents = 0; foreach (var raw in parts) { var part = raw.AsGodotDictionary(); var events = part["events"].AsGodotArray(); channelEvents += events.Count; foreach (var item in events) { var e = item.AsGodotDictionary(); if (e["type"].AsString() != "program_change" || e["beat"].AsDouble() > 0) Warn("MIDI source export retains channel events. Preview defaults to note gates, note-on pan and approximate initial program patches. CC64 sustain can be enabled explicitly in the instrument inspector; other controllers, bends, pressure and later program changes are not performed."); } error = maps.validate_channel_events(events); if (error.Length > 0) return Failure(error); }
        if (channelEvents > 131072) return Failure("A MIDI import is limited to 131072 channel events in total."); var effective = maps.canonical(tempoArray, 120);
        return new Settings { ["error"] = "", ["format"] = format, ["ppq"] = division, ["parts"] = parts, ["tempo"] = effective[0]["bpm"].AsDouble(), ["time_signature"] = new GArray { signatures[0]["numerator"].AsInt64(), signatures[0]["denominator"].AsInt64() }, ["tempos"] = tempoArray, ["time_signatures"] = meterArray, ["duration"] = (double)durationTicks / division, ["warnings"] = warnings };
    }
    public GArray sustain_copy(GArray notes, GArray events, double patternBeats, RefCounted? job)
    {
        var controls = new List<(double Beat, bool Down, int Order)>();
        for (int i = 0; i < events.Count; ++i) { var entry = events[i].AsGodotDictionary(); if (Get(entry, "type", "").AsString() == "control_change" && Get(entry, "controller", -1).AsInt64() == 64) controls.Add((Get(entry, "beat", 0.0).AsDouble(), Get(entry, "value", 0).AsInt64() >= 64, i)); }
        controls.Sort((a, b) => a.Beat != b.Beat ? a.Beat.CompareTo(b.Beat) : a.Order.CompareTo(b.Order)); double boundary = Math.Max(0, patternBeats);
        if (boundary <= 0) foreach (var raw in notes) { var note = raw.AsGodotDictionary(); boundary = Math.Max(boundary, Get(note, "start", 0.0).AsDouble() + Math.Max(0, Get(note, "duration", 0.0).AsDouble())); }
        var intervals = new List<(double Start, double End)>(); double start = -1;
        foreach (var control in controls) { if (control.Beat > boundary) break; if (control.Down) { if (start < 0) start = control.Beat; } else if (start >= 0) { if (control.Beat > start) intervals.Add((start, control.Beat)); start = -1; } }
        if (start >= 0 && boundary > start) intervals.Add((start, boundary)); var result = new GArray();
        for (int i = 0; i < notes.Count; ++i)
        {
            if (job != null && i % 128 == 0 && job.Call("is_cancelled").AsBool()) return new GArray(); var note = notes[i].AsGodotDictionary().Duplicate(true); double begin = Get(note, "start", 0.0).AsDouble(), duration = Get(note, "duration", 0.0).AsDouble(), end = begin + Math.Max(0, duration); int low = 0, high = intervals.Count;
            while (low < high) { int middle = low + (high - low) / 2; if (intervals[middle].Start <= end) low = middle + 1; else high = middle; }
            if (low > 0 && end < intervals[low - 1].End) note["duration"] = Math.Max(duration, intervals[low - 1].End - begin); result.Add(note);
        }
        return result;
    }
    public double beat_to_seconds(double beat, GArray tempos) { using var timing = KiwiAudioTempoMap.create(tempos,120.0,1.0); using var maps = new AudioTempoMapOperations(); return maps.beat_to_seconds(timing, beat); }
    public double seconds_to_beat(double seconds, GArray tempos) { using var timing = KiwiAudioTempoMap.create(tempos,120.0,1.0); using var maps = new AudioTempoMapOperations(); return maps.seconds_to_beat(timing, seconds); }
}
