using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioPlaybackOperations : RefCounted
{
    private readonly AudioEffectsOperations _effects = new();
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(new StringName(key), out var v) ? v : fallback;
    private static GodotObject? Document(Node o) => o.Get("document").AsGodotObject();
    private static Node SystemNode(Node o) => o.Get("system").As<Node>();
    private static GodotObject Model(Node o) => o.Get("model").AsGodotObject();
    private static AudioStreamPlayer Exact(Node o) => o.Get("exact_preview").As<AudioStreamPlayer>();
    private static GodotObject FilePreview(Node o) => o.Get("file_preview").AsGodotObject();
    private static double Position(Node o) => o.Get("position").AsDouble();
    private static bool Playing(Node o) => o.Get("playing").AsBool();
    private static Settings Buses(Node o) => o.Get("_track_buses").AsGodotDictionary();
    public void ready(Node o)
    {
        var system = SystemNode(o); var click = o.Get("_click").As<AudioStreamPlayer>(); var exact = Exact(o); var file = FilePreview(o); o.AddChild(system); o.AddChild(click); o.AddChild(exact); o.AddChild((Node)file);
        file.Connect("released", Callable.From<string>(path => o.EmitSignal("preview_file_released", path)));
        file.Connect("failed", Callable.From<string>(message => { stop(o, false); o.EmitSignal("preview_failed", message); }));
        file.Connect("finished", Callable.From(() => { o.Set("position", o.Get("_exact_start").AsDouble() + o.Get("_file_length").AsDouble()); o.Set("exact_preview_active", false); o.Set("playing", false); o.EmitSignal("position_changed", Position(o)); o.EmitSignal("state_changed"); }));
        click.VolumeDb = -20; var samples = new Vector2[1000]; for (int i = 0; i < samples.Length; ++i) { float value = (float)(Math.Sin(Math.Tau * 1400 * i / 44100) * Math.Exp(-i / 150.0) * .4); samples[i] = new Vector2(value, value); } using var cache = new AudioSourceCacheOperations(); click.Stream = cache.to_wav(samples, 44100, true);
        exact.Finished += () => { var document = Document(o); if (Playing(o) && o.Get("loop_enabled").AsBool() && document != null && document.Get("loop_end").AsDouble() > document.Get("loop_start").AsDouble()) { exact.Play(); o.Set("position", o.Get("_exact_start")); o.Set("_last_beat", ""); } else { o.Set("exact_preview_active", false); o.Set("playing", false); o.EmitSignal("state_changed"); } };
    }
    public void set_document(Node o, GodotObject? value)
    {
        bool wasPlaying = Playing(o) || o.Get("exact_pending").AsBool(); stop(o, false); o.Set("document", value == null ? default(Variant) : Variant.From(value));
        o.Set("_conductor", value != null ? value.Call("conductor") : KiwiAudioConductor.create(120.0,new Vector2I(4,4),new GArray(),new GArray())); o.Set("_last_beat", "");
        var model = Model(o); var actors = model.Get("actors").AsGodotArray(); var clips = model.Get("clips").AsGodotArray(); var sources = o.Get("_runtime_sources").AsGodotArray(); actors.Clear(); clips.Clear(); sources.Clear(); var system = SystemNode(o); var overrides = system.Get("clip_stream_overrides").AsGodotDictionary(); overrides.Clear(); if (value == null) return;
        var sourceActors = value.Get("actors").AsGodotArray(); var sourceClips = value.Get("clips").AsGodotArray(); 
        foreach (var raw in sourceActors) { var actor = raw.AsGodotObject(); var copy = new ActorData(); copy.Set("id", actor.Get("id")); copy.Set("type_id", new StringName("audio")); copy.Set("display_name", actor.Get("display_name")); copy.Set("values", actor.Get("values").AsGodotDictionary().Duplicate(true)); actors.Add(copy); sources.Add(actor); }
        foreach (var clip in sourceClips) clips.Add(clip); var audio = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs");
        for (int i = 0; i < Math.Min(sourceActors.Count, sourceClips.Count); ++i) if (audio.Call("needs_file_preview", Get(sourceActors[i].AsGodotObject().Get("values").AsGodotDictionary(), "audio")).AsBool()) overrides[sourceClips[i].AsGodotObject().Get("id")] = default(Variant);
        var topology = new GArray(); foreach (var raw in value.Get("tracks").AsGodotArray()) { var track = raw.AsGodotDictionary(); topology.Add(new GArray { track["id"], Get(track, "output", "") }); } string signature = GD.VarToStr(topology);
        if (o.Get("_master").AsString().Length == 0 || signature != o.Get("_bus_signature").AsString()) { rebuild_buses(o); o.Set("_bus_signature", signature); }
        if (wasPlaying && o.Get("exact_required").AsBool()) { o.Set("exact_pending", true); o.EmitSignal("exact_requested", Position(o)); } else o.Set("playing", wasPlaying); synchronize(o);
    }
    public void set_output_bus(Node o, string destination)
    {
        string output = AudioServer.GetBusIndex(destination) >= 0 ? destination : "Master"; o.Set("_external_output", output);
        foreach (string key in new[] { "_master", "_exact_bus" }) { string name = o.Get(key).AsString(); if (name.Length > 0) AudioServer.SetBusSend(AudioServer.GetBusIndex(name), output); }
    }
    public string new_bus(Node o, string label, string destination)
    {
        string name = "KiwiAudio_" + o.GetInstanceId() + "_" + label; AudioServer.AddBus(); int index = AudioServer.BusCount - 1; AudioServer.SetBusName(index, name); AudioServer.SetBusSend(index, destination); o.Get("_bus_names").AsGodotArray().Add(name); return name;
    }
    public void rebuild_buses(Node o)
    {
        clear_buses(o); var document = Document(o); if (document == null) return; string output = o.Get("_external_output").AsString(), exact = new_bus(o, "Exact", output), master = new_bus(o, "Master", output); o.Set("_exact_bus", exact); o.Set("_master", master); int masterIndex = AudioServer.GetBusIndex(master); install_effects(masterIndex, Get(document.Get("master").AsGodotDictionary(), "effects", new GArray()).AsGodotArray()); AudioServer.AddBusEffect(masterIndex, new AudioEffectHardLimiter { CeilingDb = -.3f });
        var tracks = document.Get("tracks").AsGodotArray(); var remaining = tracks.Duplicate(); int pass = 0; var buses = Buses(o);
        while (remaining.Count > 0 && pass <= tracks.Count) { ++pass; foreach (var raw in remaining.Duplicate()) { var track = raw.AsGodotDictionary(); string target = Get(track, "output", "").AsString(); if (target.Length > 0 && !buses.ContainsKey(target)) continue; string bus = new_bus(o, track["id"].AsString(), Get(buses, target, master).AsString()); buses[track["id"]] = bus; int index = AudioServer.GetBusIndex(bus); install_effects(index, Get(track, "effects", new GArray()).AsGodotArray()); AudioServer.AddBusEffect(index, new AudioEffectPanner { Pan = (float)Get(track, "pan", 0).AsDouble() }); remaining.Remove(raw); } }
        foreach (var raw in remaining) { var track = raw.AsGodotDictionary(); buses[track["id"]] = new_bus(o, track["id"].AsString(), master); }
        SystemNode(o).Call("set_output_bus", master); o.Get("_click").As<AudioStreamPlayer>().Bus = master;
    }
    public void install_effects(int bus, GArray stack) { foreach (var raw in stack) { var effect = _effects.native_effect(raw.AsGodotDictionary()); if (effect != null) AudioServer.AddBusEffect(bus, effect); } }
    public void clear_buses(Node o)
    {
        var system = SystemNode(o); foreach (var id in system.Get("players").AsGodotDictionary().Keys) system.Call("_remove_player", id); Buses(o).Clear(); o.Get("_track_effects").AsGodotDictionary().Clear(); var names = o.Get("_bus_names").AsGodotArray(); foreach (var raw in names) { int index = AudioServer.GetBusIndex(raw.AsString()); if (index > 0) AudioServer.RemoveBus(index); } names.Clear(); o.Set("_master", ""); o.Set("_exact_bus", "");
    }
    public void play(Node o)
    {
        var document = Document(o); if (document == null) return; if (Playing(o) || o.Get("exact_pending").AsBool()) { stop(o, false); return; } if (Position(o) >= document.Call("duration").AsDouble()) o.Set("position", o.Get("loop_enabled").AsBool() ? document.Get("loop_start") : Variant.From(0.0));
        if (o.Get("exact_required").AsBool()) { o.Set("exact_pending", true); o.EmitSignal("exact_requested", Position(o)); o.EmitSignal("state_changed"); return; } o.Set("playing", true); o.Set("_last_beat", ""); synchronize(o); o.EmitSignal("state_changed");
    }
    public void stop(Node o, bool reset)
    {
        o.Get("rendered_route_meters").AsGodotDictionary().Clear(); o.Set("_recording_file_token", new Settings()); o.Set("_recording_file_owner", default(Variant)); o.Set("playing", false); FilePreview(o).Call("close_file"); var exact = Exact(o); exact.Stop(); exact.Stream = null; o.Set("exact_preview_active", false); o.Set("exact_pending", false); o.Get("_click").As<AudioStreamPlayer>().Stop(); if (reset) o.Set("position", 0.0); SystemNode(o).Call("synchronize", Model(o), Position(o), false); o.EmitSignal("position_changed", Position(o)); o.EmitSignal("state_changed");
    }
    public void seek(Node o, double seconds, bool scrub)
    {
        o.Set("_last_beat", ""); o.Set("position", Math.Max(0, seconds)); var file = FilePreview(o); var exact = Exact(o); double position = Position(o), start = o.Get("_exact_start").AsDouble();
        if (o.Get("exact_preview_active").AsBool()) { double length = file.Get("active").AsBool() ? o.Get("_file_length").AsDouble() : exact.Stream?.GetLength() ?? 0; if (position >= start && position < start + length) { if (file.Get("active").AsBool()) file.Call("seek_file", position - start); else exact.Seek((float)(position - start)); } else { file.Call("close_file"); exact.Stop(); o.Set("exact_preview_active", false); o.Set("exact_pending", true); o.Set("playing", false); o.EmitSignal("exact_requested", position); } }
        else if (o.Get("exact_pending").AsBool() || (o.Get("exact_required").AsBool() && Playing(o))) { o.Set("playing", false); o.Set("exact_pending", true); o.EmitSignal("exact_requested", position); }
        else { synchronize(o); if (scrub && !Playing(o) && !o.Get("exact_required").AsBool()) SystemNode(o).Call("scrub", Model(o), position); } o.EmitSignal("position_changed", position);
    }
    public void play_exact(Node o, AudioStream stream, double start) { stop(o, false); o.Set("_exact_start", start); o.Set("_last_beat", ""); o.Set("position", start); var exact = Exact(o); exact.Stream = stream; exact.Bus = Output(o); exact.Play(); o.Set("exact_preview_active", true); o.Set("playing", true); o.EmitSignal("state_changed"); }
    private static string Output(Node o) => o.Get("_exact_bus").AsString().Length > 0 ? o.Get("_exact_bus").AsString() : o.Get("_external_output").AsString();
    public string play_file(Node o, string path, double start, Settings info)
    {
        stop(o, false); o.Set("_exact_start", start); o.Set("position", start); o.Set("_last_beat", ""); o.Set("_file_length", Get(info, "duration", 0.0).AsDouble()); var file = FilePreview(o); file.Set("loop_enabled", o.Get("loop_enabled")); string error = file.Call("open_file", path, Output(o), info, true).AsString(); if (error.Length > 0) return error; o.Set("exact_preview_active", true); o.Set("exact_pending", false); o.Set("playing", true); synchronize(o); o.EmitSignal("state_changed"); return "";
    }
    public string prepare_recording_file(Node o, string path, double start, Settings info, RefCounted owner)
    {
        stop(o, false); o.Set("_exact_start", start); o.Set("position", start); o.Set("_last_beat", ""); o.Set("_file_length", Get(info, "duration", 0.0).AsDouble()); var file = FilePreview(o); file.Set("loop_enabled", false); string error = file.Call("open_file", path, Output(o), info, false, owner, false).AsString(); if (error.Length > 0) return error; o.Set("exact_preview_active", true); o.Set("exact_pending", false); o.Set("playing", false); o.Set("_recording_file_token", file.Call("prepared_token")); o.Set("_recording_file_owner", Variant.From(GodotObject.WeakRef(owner))); synchronize(o); o.EmitSignal("state_changed"); return "";
    }
    public bool recording_file_ready(Node o, RefCounted owner) { if (!o.Get("exact_preview_active").AsBool() || Playing(o) || o.Get("_recording_file_owner").AsGodotObject() is not WeakRef weak || o.Get("_recording_file_token").AsGodotDictionary().Count == 0) return false; using var reference = weak.GetRef(); return reference.AsGodotObject() == owner && FilePreview(o).Call("is_primed", o.Get("_recording_file_token")).AsBool(); }
    public string start_recording_file(Node o, RefCounted owner) { if (!recording_file_ready(o, owner)) return "The prepared recording playback changed or was cancelled."; string error = FilePreview(o).Call("start_primed", o.Get("_recording_file_token")).AsString(); if (error.Length > 0) return error; o.Set("playing", true); o.EmitSignal("state_changed"); return ""; }
    public void process(Node o, double delta)
    {
        var document = Document(o); if (!Playing(o) || document == null) return; double position;
        if (o.Get("exact_preview_active").AsBool()) { var file = FilePreview(o); if (file.Get("active").AsBool()) { file.Set("loop_enabled", o.Get("loop_enabled")); position = o.Get("_exact_start").AsDouble() + file.Call("position_seconds").AsDouble(); } else position = o.Get("_exact_start").AsDouble() + Exact(o).GetPlaybackPosition(); o.Set("position", position); }
        else { position = Position(o) + delta; double loopStart = document.Get("loop_start").AsDouble(), loopEnd = document.Get("loop_end").AsDouble(); if (o.Get("loop_enabled").AsBool() && loopEnd > loopStart && position >= loopEnd) { double span = loopEnd - loopStart; position = loopStart + (position - loopStart) - Math.Floor((position - loopStart) / span) * span; o.Set("_last_beat", ""); } else if (position >= document.Call("duration").AsDouble() + .1) { o.Set("position", position); stop(o, false); return; } o.Set("position", position); synchronize(o); }
        bool metronome = o.Get("metronome").AsBool(); var conductor = o.Get("_conductor").As<RefCounted>(); if (metronome && conductor.Get("error").AsString().Length == 0) { using var operations = new AudioConductorOperations(); var beat = operations.beat_info(conductor, operations.seconds_to_beat(conductor, Position(o))); string key = beat["key"].AsString(); if (key != o.Get("_last_beat").AsString()) { var click = o.Get("_click").As<AudioStreamPlayer>(); click.PitchScale = beat["downbeat"].AsBool() ? 1.3f : 1; click.Play(); o.Set("_last_beat", key); } } else if (!metronome) o.Set("_last_beat", ""); o.EmitSignal("position_changed", Position(o));
    }
    public string musical_position(Node o, double seconds) { using var conductor = new AudioConductorOperations(); return conductor.position_text(o.Get("_conductor").As<RefCounted>(), seconds); }
    public void synchronize(Node o)
    {
        var document = Document(o); string master = o.Get("_master").AsString(); if (document == null || master.Length == 0) return; var system = SystemNode(o); var model = Model(o); double position = Position(o);
        if (o.Get("exact_preview_active").AsBool() || o.Get("exact_pending").AsBool() || (o.Get("exact_required").AsBool() && Playing(o))) { system.Call("synchronize", model, position, false); return; }
        var tracks = document.Get("tracks").AsGodotArray(); bool solo = false; foreach (var raw in tracks) if (Get(raw.AsGodotDictionary(), "solo", false).AsBool()) solo = true;
        double Value(Settings owner, string key, double time, double fallback) => _effects.automation_value(Get(Get(owner, "automation", new Settings()).AsGodotDictionary(), key, new GArray()).AsGodotArray(), time, Get(owner, key, fallback).AsDouble());
        var masterState = document.Get("master").AsGodotDictionary(); int masterIndex = AudioServer.GetBusIndex(master); update_effects(o, masterIndex, _effects.evaluated_stack(Get(masterState, "effects", new GArray()).AsGodotArray(), position)); AudioServer.SetBusVolumeDb(masterIndex, (float)Value(masterState, "volume_db", position, -3));
        foreach (var raw in tracks) { var track = raw.AsGodotDictionary(); int index = AudioServer.GetBusIndex(Get(Buses(o), track["id"].AsString(), "").AsString()); if (index < 0) continue; update_effects(o, index, _effects.evaluated_stack(Get(track, "effects", new GArray()).AsGodotArray(), position)); AudioServer.SetBusVolumeDb(index, (float)Value(track, "volume_db", position, 0)); AudioServer.SetBusMute(index, Get(track, "mute", false).AsBool() || (solo && !Get(track, "solo", false).AsBool() && Get(track, "kind", "").AsString() != "group")); int count = AudioServer.GetBusEffectCount(index); if (count > 0 && AudioServer.GetBusEffect(index, count - 1) is AudioEffectPanner pan) pan.Pan = (float)Value(track, "pan", position, 0); }
        var actors = model.Get("actors").AsGodotArray(); var clips = model.Get("clips").AsGodotArray(); var sources = o.Get("_runtime_sources").AsGodotArray();
        for (int i = 0; i < Math.Min(actors.Count, sources.Count); ++i)
        {
            var source = sources[i].AsGodotObject().Get("values").AsGodotDictionary(); var values = actors[i].AsGodotObject().Get("values").AsGodotDictionary(); var clip = clips[i].AsGodotObject(); double local = position - clip.Get("start_time").AsDouble(); var id = clip.Get("id");
            values[new StringName("volume_db")] = Value(source, "volume_db", local, 0); values[new StringName("pitch")] = Value(source, "pitch", local, 1); values[new StringName("muted")] = Get(source, "muted", false); foreach (string key in new[] { "fade_in", "fade_out", "fade_curve", "loop" }) values[new StringName(key)] = Get(source, key, key is "fade_in" or "fade_out" ? Variant.From(0.0) : Variant.From(false));
            system.Get("clip_pan").AsGodotDictionary()[id] = Value(source, "pan", local, 0); system.Get("clip_output_buses").AsGodotDictionary()[id] = Get(Buses(o), Get(source, "track_id", "").AsString(), master); system.Get("clip_effects").AsGodotDictionary()[id] = _effects.evaluated_stack(Get(source, "effects", new GArray()).AsGodotArray(), local);
        }
        system.Call("synchronize", model, position, Playing(o));
    }
    public bool meter_supported(Node o, string track) => track.Length == 0 || !o.Get("exact_preview_active").AsBool() || o.Get("rendered_route_meters").AsGodotDictionary().ContainsKey(track);
    public Vector2 meter(Node o, string track)
    {
        var quiet = new Vector2(-80, -80); if (!meter_supported(o, track)) return quiet; bool exact = o.Get("exact_preview_active").AsBool(); if (exact && track.Length > 0) { var values = o.Get("rendered_route_meters").AsGodotDictionary()[track].AsVector2Array(); long index = (long)Math.Floor((Position(o) - o.Get("rendered_meter_start").AsDouble()) * o.Get("rendered_meter_hz").AsDouble()); return Playing(o) && index >= 0 && index < values.Length ? values[index] : quiet; }
        string name = track.Length == 0 ? o.Get(exact ? "_exact_bus" : "_master").AsString() : Get(Buses(o), track, "").AsString(); int bus = AudioServer.GetBusIndex(name); return bus < 0 ? quiet : new Vector2(AudioServer.GetBusPeakVolumeLeftDb(bus, 0), AudioServer.GetBusPeakVolumeRightDb(bus, 0));
    }
    public void exit_tree(Node o) { stop(o, false); clear_buses(o); }
    public void update_effects(Node o, int bus, GArray stack)
    {
        string signature = GD.VarToStr(stack); var signatures = o.Get("_track_effects").AsGodotDictionary(); if (signatures.TryGetValue(bus, out var previous) && previous.AsString() == signature) return;
        var generated = new System.Collections.Generic.List<AudioEffect>(); foreach (var raw in stack) { var effect = _effects.native_effect(raw.AsGodotDictionary()); if (effect != null) generated.Add(effect); } int count = AudioServer.GetBusEffectCount(bus) - 1; bool same = count == generated.Count;
        if (same) for (int i = 0; i < count; ++i) if (AudioServer.GetBusEffect(bus, i).GetClass() != generated[i].GetClass()) { same = false; break; }
        if (same) { try { for (int i = 0; i < count; ++i) _effects.update_native_properties(AudioServer.GetBusEffect(bus, i), generated[i]); } finally { foreach (var effect in generated) effect.Dispose(); } }
        else { for (int i = 0; i < Math.Max(0, count); ++i) AudioServer.RemoveBusEffect(bus, 0); for (int i = 0; i < generated.Count; ++i) AudioServer.AddBusEffect(bus, generated[i], i); } signatures[bus] = signature;
    }
}
