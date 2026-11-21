using Godot;
using System;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioMidiOperations
{
    private const double MaxExportBeat = 0x0ffffffe / 480.0;
    private static double Finite(Variant value, double fallback) { double v = value.VariantType is Variant.Type.Int or Variant.Type.Float ? value.AsDouble() : fallback; return double.IsFinite(v) ? v : fallback; }
    public int instrument_program(string id) => id switch { "piano" => 0, "organ" => 19, "bells" => 10, "strings" => 48, "brass" => 61, "bass" => 38, "lead" or "chip" => 80, "pad" => 89, "pluck" => 24, "cinematic" => 103, _ => 80 };
    public long ticks(Variant beat) => (long)Math.Clamp(Math.Round(Finite(beat, 0) * 480, MidpointRounding.AwayFromZero), 0, 0x0ffffffe);
    public byte[] vlq(long value)
    {
        var bytes = new List<byte> { (byte)(value & 127) }; long remaining = value >> 7; while (remaining > 0) { bytes.Insert(0, (byte)((remaining & 127) | 128)); remaining >>= 7; } return bytes.ToArray();
    }
    private readonly record struct MidiEvent(long Tick, int Order, byte[] Bytes, int Sequence);
    private byte[] Encode(List<MidiEvent> events, long endTick)
    {
        events.Sort((a, b) => a.Tick != b.Tick ? a.Tick.CompareTo(b.Tick) : a.Order != b.Order ? a.Order.CompareTo(b.Order) : a.Sequence.CompareTo(b.Sequence));
        var output = new List<byte>(); long previous = 0;
        foreach (var item in events) { output.AddRange(vlq(Math.Max(0, item.Tick - previous))); output.AddRange(item.Bytes); previous = item.Tick; }
        output.AddRange(vlq(Math.Max(0, endTick - previous))); output.AddRange(new byte[] { 0xff, 0x2f, 0 }); return output.ToArray();
    }
    public byte[] encode_track(GArray events, long endTick)
    {
        var ordered = new List<Settings>(); for (int i = 0; i < events.Count; ++i) { var item = events[i].AsGodotDictionary(); item["sequence"] = i; ordered.Add(item); }
        ordered.Sort((a, b) => a["tick"].AsInt64() != b["tick"].AsInt64() ? a["tick"].AsInt64().CompareTo(b["tick"].AsInt64()) : a["order"].AsInt32() != b["order"].AsInt32() ? a["order"].AsInt32().CompareTo(b["order"].AsInt32()) : a["sequence"].AsInt32().CompareTo(b["sequence"].AsInt32()));
        events.Clear(); var native = new List<MidiEvent>(); foreach (var item in ordered) { events.Add(item); native.Add(new MidiEvent(item["tick"].AsInt64(), item["order"].AsInt32(), item["bytes"].AsByteArray(), item["sequence"].AsInt32())); } return Encode(native, endTick);
    }
    public byte[] write_bytes(GArray parts, Variant tempo, Variant signature)
    {
        if (parts.Count > 128) return Array.Empty<byte>(); var sources = new GArray();
        foreach (var raw in parts) { if (raw.VariantType != Variant.Type.Dictionary) return Array.Empty<byte>(); var part = raw.AsGodotDictionary(); if (Get(part, "instrument", new Settings()).VariantType != Variant.Type.Dictionary) return Array.Empty<byte>(); var notes = Get(part, "notes", new GArray()); if (notes.VariantType != Variant.Type.Array) return Array.Empty<byte>(); sources.Add(new Settings { ["notes"] = notes, ["midi_events"] = Get(part, "events", new GArray()) }); }
        using var maps = new AudioTempoMapOperations(); if (maps.validate_budget(sources, new Settings()).Length > 0) return Array.Empty<byte>();
        var tempos = tempo.VariantType == Variant.Type.Array ? tempo.AsGodotArray() : new GArray { new Settings { ["beat"] = 0.0, ["bpm"] = Finite(tempo, 120) } }; GArray meters;
        if (signature.VariantType == Variant.Type.Array && signature.AsGodotArray().Count > 0 && signature.AsGodotArray()[0].VariantType == Variant.Type.Dictionary) meters = signature.AsGodotArray();
        else if (signature.VariantType == Variant.Type.Array && signature.AsGodotArray().Count >= 2) meters = new GArray { new Settings { ["beat"] = 0.0, ["numerator"] = signature.AsGodotArray()[0].AsInt64(), ["denominator"] = signature.AsGodotArray()[1].AsInt64() } };
        else meters = new GArray { new Settings { ["beat"] = 0.0, ["numerator"] = 4, ["denominator"] = 4 } };
        if (maps.validate_tempos(tempos, true).Length > 0 || maps.validate_meters(meters).Length > 0) return Array.Empty<byte>();
        var conductor = new List<MidiEvent>();
        void Add(List<MidiEvent> events, long tick, int order, params byte[] bytes) => events.Add(new MidiEvent(tick, order, bytes, events.Count));
        foreach (var raw in tempos)
        {
            if (raw.VariantType != Variant.Type.Dictionary) continue; var item = raw.AsGodotDictionary(); if (Get(item, "beat", 0.0).AsDouble() > MaxExportBeat) return Array.Empty<byte>(); double microseconds = Finite(Get(item, "microseconds", 0.0), 0); if (microseconds <= 0) microseconds = 60000000 / Math.Max(.000001, Finite(Get(item, "bpm", 120.0), 120)); if (microseconds < 1 || microseconds > 0xffffff) return Array.Empty<byte>(); int value = (int)Math.Round(microseconds, MidpointRounding.AwayFromZero);
            Add(conductor, ticks(Get(item, "beat", 0.0)), 0, 0xff, 0x51, 3, (byte)((value >> 16) & 255), (byte)((value >> 8) & 255), (byte)(value & 255));
        }
        foreach (var raw in meters)
        {
            var item = raw.AsGodotDictionary(); if (Get(item, "beat", 0.0).AsDouble() > MaxExportBeat) return Array.Empty<byte>(); int denominator = Get(item, "denominator", 4).AsInt32(); if (denominator < 1 || denominator > 128 || (denominator & (denominator - 1)) != 0) return Array.Empty<byte>(); int exponent = 0; while ((1 << exponent) < denominator) ++exponent;
            Add(conductor, ticks(Get(item, "beat", 0.0)), 1, 0xff, 0x58, 4, (byte)Math.Clamp(Get(item, "numerator", 4).AsInt32(), 1, 255), (byte)exponent, (byte)Math.Clamp(Get(item, "clocks_per_click", 24).AsInt32(), 1, 255), (byte)Math.Clamp(Get(item, "thirty_seconds", 8).AsInt32(), 1, 255));
        }
        var tracks = new List<byte[]> { Encode(conductor, 0) };
        for (int index = 0; index < parts.Count; ++index)
        {
            var part = parts[index].AsGodotDictionary(); if (Finite(Get(part, "duration", 0.0), 0) > MaxExportBeat) return Array.Empty<byte>(); var instrument = Get(part, "instrument", new Settings()).AsGodotDictionary(); int defaultChannel = index % 15; if (defaultChannel >= 9) ++defaultChannel;
            int channel = Math.Clamp(Get(instrument, "midi_channel", Get(part, "role", "").AsString() == "drums" ? 9 : defaultChannel).AsInt32(), 0, 15), program = Math.Clamp(Get(instrument, "midi_program", instrument_program(Get(instrument, "id", "piano").AsString())).AsInt32(), 0, 127);
            var events = new List<MidiEvent>(); var name = System.Text.Encoding.UTF8.GetBytes(Get(part, "label", Get(part, "role", "Instrument")).AsString()); if (name.Length > 4096) return Array.Empty<byte>(); var nameEvent = new List<byte> { 0xff, 3 }; nameEvent.AddRange(vlq(name.Length)); nameEvent.AddRange(name); Add(events, 0, 0, nameEvent.ToArray()); Add(events, 0, 1, (byte)(0xc0 | channel), (byte)program);
            foreach (var raw in Get(part, "notes", new GArray()).AsGodotArray())
            {
                if (raw.VariantType != Variant.Type.Dictionary) continue; var entry = raw.AsGodotDictionary(); double end = Finite(Get(entry, "start", 0.0), 0) + Math.Max(0, Finite(Get(entry, "duration", .25), .25)); if (end > MaxExportBeat) return Array.Empty<byte>(); long start = ticks(Get(entry, "start", 0.0)), finish = Math.Max(start + 1, ticks(end)); int pitch = Math.Clamp(Get(entry, "pitch", 60).AsInt32(), 0, 127), velocity = Math.Clamp((int)Math.Round(Math.Clamp(Finite(Get(entry, "velocity", .8), .8), 0, 1) * 127, MidpointRounding.AwayFromZero), 0, 127); if (velocity == 0) continue;
                Add(events, start, 4, (byte)(0x90 | channel), (byte)pitch, (byte)velocity); Add(events, finish, 2, (byte)(0x80 | channel), (byte)pitch, 0);
            }
            foreach (var raw in Get(part, "events", new GArray()).AsGodotArray())
            {
                if (raw.VariantType != Variant.Type.Dictionary) continue; var item = raw.AsGodotDictionary(); if (Finite(Get(item, "beat", 0.0), 0) > MaxExportBeat) return Array.Empty<byte>(); byte[] data = Array.Empty<byte>(); int C(string key, int fallback, int high = 127) => Math.Clamp(Get(item, key, fallback).AsInt32(), 0, high);
                switch (Get(item, "type", "").AsString())
                {
                    case "control_change": data = new byte[] { (byte)(0xb0 | channel), (byte)C("controller", 0), (byte)C("value", 0) }; break;
                    case "program_change": if (ticks(Get(item, "beat", 0.0)) == 0 && Get(item, "program", program).AsInt32() == program) continue; data = new byte[] { (byte)(0xc0 | channel), (byte)C("program", program) }; break;
                    case "pitch_bend": int value = C("value", 8192, 16383); data = new byte[] { (byte)(0xe0 | channel), (byte)(value & 127), (byte)((value >> 7) & 127) }; break;
                    case "poly_pressure": data = new byte[] { (byte)(0xa0 | channel), (byte)C("pitch", 60), (byte)C("value", 0) }; break;
                    case "channel_pressure": data = new byte[] { (byte)(0xd0 | channel), (byte)C("value", 0) }; break;
                }
                if (data.Length > 0) Add(events, ticks(Get(item, "beat", 0.0)), 3, data);
            }
            if (events.Count > 1000000) return Array.Empty<byte>(); tracks.Add(Encode(events, ticks(Get(part, "duration", 0.0))));
        }
        var output = new List<byte>(System.Text.Encoding.ASCII.GetBytes("MThd"));
        void Be16(int value) { output.Add((byte)((value >> 8) & 255)); output.Add((byte)(value & 255)); }
        void Be32(int value) { foreach (int shift in new[] { 24, 16, 8, 0 }) output.Add((byte)((value >> shift) & 255)); }
        Be32(6); Be16(1); Be16(tracks.Count); Be16(480); foreach (var track in tracks) { output.AddRange(System.Text.Encoding.ASCII.GetBytes("MTrk")); Be32(track.Length); output.AddRange(track); }
        return output.Count > 32 * 1024 * 1024 ? Array.Empty<byte>() : output.ToArray();
    }
    public Error write(string path, GArray parts, Variant tempo, Variant signature)
    {
        if (Godot.FileAccess.FileExists(path)) return Error.AlreadyExists; var bytes = write_bytes(parts, tempo, signature); if (bytes.Length == 0) return Error.InvalidData;
        using var crypto = new Crypto(); string directory = ProjectSettings.GlobalizePath("user://audio_workspace/midi_exports/" + Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant()); var created = DirAccess.MakeDirRecursiveAbsolute(directory); if (created != Error.Ok) return created;
        using var renderer = new AudioRendererOperations();
        try
        {
            string temporary = directory.PathJoin("source.mid"); Error error;
            using (var file = Godot.FileAccess.Open(temporary, Godot.FileAccess.ModeFlags.Write)) { if (file == null) return Godot.FileAccess.GetOpenError(); file.StoreBuffer(bytes); file.Flush(); error = file.GetError(); }
            if (error == Error.Ok) { var published = renderer.publish_complete(temporary, path, null); if (!published["success"].AsBool()) { GD.PushWarning(published["error"].AsString()); error = Godot.FileAccess.FileExists(path) ? Error.AlreadyExists : Error.FileCantWrite; } }
            return error;
        }
        finally { renderer.remove_owned(directory); }
    }
}
