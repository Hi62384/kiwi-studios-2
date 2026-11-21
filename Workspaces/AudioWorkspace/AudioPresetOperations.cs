using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioPresetOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(new StringName(key), out var value) ? value : fallback;
    private static Settings Failure(string error) => new Settings { ["error"] = error };
    public bool number_in(Variant value, double low, double high) => value.VariantType is Variant.Type.Int or Variant.Type.Float && double.IsFinite(value.AsDouble()) && value.AsDouble() >= low && value.AsDouble() <= high;
    private static GArray ArrayOf(Variant value) { if (value.VariantType == Variant.Type.Array) return value.AsGodotArray().Duplicate(); var result = new GArray(); if (value.VariantType == Variant.Type.PackedStringArray) foreach (string item in value.AsStringArray()) result.Add(item); return result; }
    public Settings pattern_data(GodotObject? actor, GodotObject? document)
    {
        if (actor == null) return new Settings(); var values = actor.Get("values").AsGodotDictionary(); using var maps = new AudioTempoMapOperations(); string error = maps.validate_source(values); if (error.Length > 0) return new Settings { ["_pattern_error"] = error };
        var notes = Get(values, "notes", new GArray()); if (notes.VariantType != Variant.Type.Array || notes.AsGodotArray().Count > 8192) return new Settings { ["_pattern_error"] = "Pattern notes must be an array of at most 8192 notes." };
        var result = new Settings { ["notes"] = notes.AsGodotArray().Duplicate(true), ["instrument"] = Get(values, "instrument", new Settings()).AsGodotDictionary().Duplicate(true), ["pattern_beats"] = Get(values, "pattern_beats", 4).AsDouble(), ["step_settings"] = Get(values, "step_settings", new Settings()).AsGodotDictionary().Duplicate(true), ["tags"] = ArrayOf(Get(values, "pattern_tags", new GArray())) };
        if (values.ContainsKey(new StringName("drum_instances"))) { result["drum_patterns"] = Get(values, "drum_patterns", new Settings()).AsGodotDictionary().Duplicate(true); result["drum_instances"] = Get(values, "drum_instances").AsGodotArray().Duplicate(true); }
        foreach (string key in new[] { "midi_tempos", "midi_time_signatures", "midi_events" }) if (values.TryGetValue(new StringName(key), out var raw)) result[key] = raw.AsGodotArray().Duplicate(true);
        if (document != null) { using var edits = new AudioEditSessionOperations(); result["source_bpm"] = edits.note_source_tempo(actor, document); var meter = edits.note_source_meter(actor, document); result["source_meter"] = new GArray { meter.X, meter.Y }; }
        else { if (values.TryGetValue(new StringName("source_bpm"), out var bpm)) result["source_bpm"] = bpm.AsDouble(); if (values.TryGetValue(new StringName("source_meter"), out var meter)) result["source_meter"] = meter.AsGodotArray().Duplicate(); }
        if (values.ContainsKey(new StringName("midi_tempos"))) result["midi_tempo_scale"] = Get(values, "midi_tempo_scale", 1.0).AsDouble(); if (values.ContainsKey(new StringName("midi_sustain"))) result["midi_sustain"] = Get(values, "midi_sustain").AsBool(); return result;
    }
    public string validate_pattern(Settings value)
    {
        if (value.ContainsKey("_pattern_error")) return value["_pattern_error"].AsString();
        if (value.ContainsKey("drum_instances") || value.ContainsKey("drum_patterns")) { using var linked = new AudioLinkedPatternOperations(); string problem = linked.validate(Get(value, "drum_patterns", new Settings()), Get(value, "drum_instances", new GArray())); if (problem.Length > 0) return problem; }
        using var maps = new AudioTempoMapOperations(); string error = maps.validate_source(value); if (error.Length > 0) return error;
        var notes = Get(value, "notes", new GArray()); if (notes.VariantType != Variant.Type.Array || notes.AsGodotArray().Count > 8192) return "Pattern notes must be an array of at most 8192 notes.";
        bool mapped = value.ContainsKey("midi_tempos"); if (!number_in(Get(value, "pattern_beats", 4), mapped ? .000001 : 1.0 / 12, mapped ? 10000000 : 256)) return "Invalid pattern length (ordinary patterns: 1/12 to 256 beats; MIDI patterns: 0.000001 to 10000000 beats).";
        if (Get(value, "instrument", new Settings()).VariantType != Variant.Type.Dictionary || Get(value, "step_settings", new Settings()).VariantType != Variant.Type.Dictionary) return "Invalid instrument or step settings."; var instrument = Get(value, "instrument", new Settings()).AsGodotDictionary();
        foreach (string key in new[] { "seed", "root_pitch" }) if (instrument.ContainsKey(key) && !number_in(instrument[key], int.MinValue, int.MaxValue)) return "Invalid instrument " + key + ".";
        foreach (string key in new[] { "harmonics", "wavetable", "modulators", "multisamples", "effects" }) if (instrument.ContainsKey(key) && instrument[key].VariantType != Variant.Type.Array) return "Invalid instrument " + key + ".";
        foreach (string key in new[] { "harmonics", "wavetable" }) foreach (var raw in Get(instrument, key, new GArray()).AsGodotArray()) if (!number_in(raw, -1000000, 1000000)) return "Invalid instrument " + key + " value.";
        foreach (var raw in Get(instrument, "multisamples", new GArray()).AsGodotArray()) { if (raw.VariantType != Variant.Type.Dictionary) return "Invalid multisample mapping."; var mapping = raw.AsGodotDictionary(); foreach (string key in new[] { "low", "high", "root_pitch", "velocity_low", "velocity_high" }) if (mapping.ContainsKey(key) && !number_in(mapping[key], 0, 127)) return "Invalid sample mapping " + key + "."; }
        foreach (var raw in Get(instrument, "modulators", new GArray()).AsGodotArray()) { if (raw.VariantType != Variant.Type.Dictionary) return "Invalid instrument modulator."; var mod = raw.AsGodotDictionary(); if (Get(mod, "values", new GArray()).VariantType != Variant.Type.Array || Get(mod, "points", new GArray()).VariantType != Variant.Type.Array) return "Invalid instrument modulator."; foreach (var point in Get(mod, "points", new GArray()).AsGodotArray()) if (point.VariantType != Variant.Type.Dictionary) return "Invalid modulator automation point."; }
        foreach (var raw in notes.AsGodotArray())
        {
            if (raw.VariantType != Variant.Type.Dictionary) return "Invalid pattern note."; var note = raw.AsGodotDictionary(); var bends = Get(note, "pitch_bend", new GArray()); if (bends.VariantType != Variant.Type.Array) return "Invalid pitch-bend points."; foreach (var point in bends.AsGodotArray()) if (point.VariantType != Variant.Type.Dictionary) return "Invalid pitch-bend point.";
            double limit = mapped ? 10000000 : 2048;
            foreach (var rule in new (string Key, double Default, double Low, double High)[] { ("pitch",60,0,127),("start",0,0,limit),("duration",.25,mapped?.000001:.001,limit),("velocity",.8,0,1),("pan",0,-1,1),("probability",1,0,1),("ratchets",1,1,8) }) if (!number_in(Get(note, rule.Key, rule.Default), rule.Low, rule.High)) return "Invalid note " + rule.Key + ".";
        }
        var settings = Get(value, "step_settings", new Settings()).AsGodotDictionary();
        foreach (var rule in new (string Key, double Default, double Low, double High)[] { ("steps",16,1,256),("division",.25,1.0/12,1),("swing",0,-.45,.45),("accent_variation",0,0,1),("seed",1,0,int.MaxValue) }) if (!number_in(Get(settings, rule.Key, rule.Default), rule.Low, rule.High)) return "Invalid step " + rule.Key + ".";
        var lanes = Get(settings, "lanes", new Settings()); if (lanes.VariantType != Variant.Type.Dictionary || lanes.AsGodotDictionary().Count > 128) return "Invalid step lanes.";
        foreach (var pitch in lanes.AsGodotDictionary().Keys) { if (!long.TryParse(pitch.AsString(), System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out long number) || number < 0 || number > 127 || lanes.AsGodotDictionary()[pitch].VariantType != Variant.Type.Dictionary) return "Invalid step lane."; var lane = lanes.AsGodotDictionary()[pitch].AsGodotDictionary(); foreach (string flag in new[] { "mute", "solo" }) if (lane.ContainsKey(flag) && lane[flag].VariantType != Variant.Type.Bool) return "Invalid lane " + flag + "."; }
        var tags = Get(value, "tags", new GArray()); if (tags.VariantType != Variant.Type.Array || tags.AsGodotArray().Count > 32) return "Pattern tags must be an array of at most 32 strings."; foreach (var tag in tags.AsGodotArray()) if (tag.VariantType != Variant.Type.String || tag.AsString().Length > 128) return "Invalid pattern tag."; return "";
    }
    public bool data_only(Variant value, int depth, GArray budget)
    {
        long visits = budget[0].AsInt64() + 1; budget[0] = visits; if (depth > 16 || visits > 100000) return false;
        switch (value.VariantType)
        {
            case Variant.Type.Nil: case Variant.Type.Bool: case Variant.Type.Int: return true;
            case Variant.Type.Float: return double.IsFinite(value.AsDouble());
            case Variant.Type.String: case Variant.Type.StringName: return value.AsString().Length <= 8192;
            case Variant.Type.Array: var array = value.AsGodotArray(); if (array.Count > 8192) return false; foreach (var item in array) if (!data_only(item, depth + 1, budget)) return false; return true;
            case Variant.Type.Dictionary: var dictionary = value.AsGodotDictionary(); if (dictionary.Count > 1024) return false; foreach (var key in dictionary.Keys) if (key.VariantType is not Variant.Type.String and not Variant.Type.StringName || key.AsString().Length > 128 || !data_only(dictionary[key], depth + 1, budget)) return false; return true;
            default: return false;
        }
    }
    public bool json_audio_paths(Variant value)
    {
        if (value.VariantType == Variant.Type.Array) { foreach (var item in value.AsGodotArray()) if (!json_audio_paths(item)) return false; }
        else if (value.VariantType == Variant.Type.Dictionary) { var d = value.AsGodotDictionary(); foreach (var key in d.Keys) if (key.AsString() == "sample") { var path = d[key]; if (path.VariantType != Variant.Type.String || (path.AsString().Length > 0 && path.AsString().GetExtension().ToLowerInvariant() is not "wav" and not "mp3" and not "ogg" and not "flac")) return false; } else if (!json_audio_paths(d[key])) return false; }
        return true;
    }
    public bool json_depth_allowed(string text)
    {
        int depth = 0; bool quoted = false, escaped = false;
        foreach (char c in text) { if (quoted) { if (escaped) escaped = false; else if (c == '\\') escaped = true; else if (c == '"') quoted = false; } else if (c == '"') quoted = true; else if (c is '{' or '[') { if (++depth > 16) return false; } else if (c is '}' or ']') --depth; }
        return true;
    }
    public Settings to_json_text(GodotObject? preset)
    {
        if (preset == null || preset.Get("kind").AsString() != "pattern") return Failure("Only data-only pattern presets can be exported as JSON."); var source = preset.Get("data").AsGodotDictionary(); string problem = validate_pattern(source); if (problem.Length > 0) return Failure(problem);
        var data = source.Duplicate(true); var tags = ArrayOf(preset.Get("tags")); if (!data.ContainsKey("tags")) data["tags"] = tags; problem = validate_pattern(data); if (problem.Length > 0) return Failure(problem);
        var payload = new Settings { ["format"] = "kiwi_audio_pattern", ["version"] = 1, ["label"] = preset.Get("label"), ["tags"] = tags, ["data"] = data };
        if (!data_only(payload, 0, new GArray { 0 })) return Failure("JSON export needs bounded data-only settings. Embedded sample resources cannot be exported; save a native preset instead."); if (!json_audio_paths(payload)) return Failure("JSON sample references must be ordinary WAV, MP3, Ogg or FLAC paths, never script-bearing resources."); string encoded = Json.Stringify(payload, "  "); if (System.Text.Encoding.UTF8.GetByteCount(encoded) > 1024 * 1024) return Failure("Pattern JSON exceeds 1 MiB."); return new Settings { ["error"] = "", ["json"] = encoded };
    }
    public Settings from_json_text(string text)
    {
        if (System.Text.Encoding.UTF8.GetByteCount(text) > 1024 * 1024) return Failure("Pattern JSON exceeds 1 MiB."); if (!json_depth_allowed(text)) return Failure("Pattern JSON nesting exceeds the safe limit."); using var parser = new Json(); if (parser.Parse(text) != Error.Ok) return Failure("Invalid JSON: " + parser.GetErrorMessage()); var raw = parser.Data;
        if (raw.VariantType != Variant.Type.Dictionary || !data_only(raw, 0, new GArray { 0 })) return Failure("Pattern JSON must contain bounded data only."); var value = raw.AsGodotDictionary(); if (Get(value, "format", "").AsString() != "kiwi_audio_pattern" || !number_in(Get(value, "version"), 1, 1)) return Failure("Unsupported pattern JSON format or version."); if (Get(value, "data").VariantType != Variant.Type.Dictionary) return Failure("Missing pattern data."); if (!json_audio_paths(value)) return Failure("JSON sample references must be ordinary WAV, MP3, Ogg or FLAC paths, never script-bearing resources.");
        var data = value["data"].AsGodotDictionary(); string problem = validate_pattern(data); if (problem.Length > 0) return Failure(problem); var tags = Get(value, "tags", Get(data, "tags", new GArray())); if (tags.VariantType != Variant.Type.Array || tags.AsGodotArray().Count > 32) return Failure("Invalid pattern tags."); var strings = new System.Collections.Generic.List<string>(); foreach (var tag in tags.AsGodotArray()) { if (tag.VariantType != Variant.Type.String || tag.AsString().Length > 128) return Failure("Invalid pattern tag."); strings.Add(tag.AsString()); }
        var preset = new KiwiAudioPreset(); using var crypto = new Crypto(); preset.Set("id", Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant()); preset.Set("kind", "pattern"); string label = Get(value, "label", "Imported pattern").AsString(); preset.Set("label", label[..Math.Min(128, label.Length)]); preset.Set("tags", strings.ToArray()); preset.Set("data", data.Duplicate(true)); return new Settings { ["error"] = "", ["preset"] = preset };
    }
    public Settings import_pattern_json(string path) { using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read); if (file == null) return Failure("Could not read the pattern JSON file."); if (file.GetLength() > 1024 * 1024) return Failure("Pattern JSON exceeds 1 MiB."); return from_json_text(file.GetAsText()); }
    public string export_pattern_json(string path, GodotObject preset) { var encoded = to_json_text(preset); if (encoded["error"].AsString().Length > 0) return encoded["error"].AsString(); if (Godot.FileAccess.FileExists(path)) return "Choose a new filename; an existing file will not be overwritten."; using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Write); if (file == null) return "Could not write the pattern JSON file."; file.StoreString(encoded["json"].AsString()); return ""; }
    public string apply_pattern(RefCounted session, GodotObject? preset, double at, string trackId, bool createClip)
    {
        if (preset == null || preset.Get("kind").AsString() != "pattern") return "Choose a pattern preset.";
        var data = preset.Get("data").AsGodotDictionary(); string problem = validate_pattern(data); if (problem.Length > 0) return problem;
        using var edits = new AudioEditSessionOperations(); var actor = edits.primary(session, true).AsGodotObject(); var clip = edits.primary(session, false).AsGodotObject();
        if (!createClip && (actor == null || clip == null)) createClip = true;
        if (!createClip && !edits.can_edit(session, clip!.Get("id").AsString())) return "The selected clip is locked or frozen.";
        var document = session.Get("document").AsGodotObject(); var track = document.Call("track_for_id", trackId.Length > 0 ? trackId : session.Get("selected_track").AsString()).AsGodotDictionary();
        if (createClip && track.Count > 0 && (Get(track, "locked", false).AsBool() || track.ContainsKey("frozen_track"))) return "The destination track is locked or frozen.";
        problem = document.Call("midi_timing_error", new GArray { data }, createClip ? "" : actor!.Get("id").AsString()).AsString(); if (problem.Length > 0) return problem;
        using var conductorOps = new AudioConductorOperations(); var conductor = document.Call("conductor").As<RefCounted>();
        double sourceBpm = Get(data, "source_bpm", conductorOps.tempo_at(conductor, createClip ? at : clip!.Get("start_time").AsDouble())).AsDouble();
        using var maps = new AudioTempoMapOperations(); using var timing = KiwiAudioTempoMap.create(Get(data, "midi_tempos", new GArray()),sourceBpm,Get(data, "midi_tempo_scale", 1.0).AsDouble());
        if (timing.Get("error").AsString().Length > 0) return timing.Get("error").AsString(); double seconds = maps.beat_to_seconds(timing, Get(data, "pattern_beats", 4).AsDouble()); if (seconds > 300) return "The pattern exceeds the 300-second render limit at this tempo.";
        AudioStreamWav? empty = null; if (createClip) { using var cache = new AudioSourceCacheOperations(); empty = cache.to_wav(new Vector2[Math.Max(2, (int)Math.Ceiling(seconds * 8000))], 8000, true); }
        edits.begin(session, "Apply note pattern");
        if (createClip)
        {
            if (track.Count == 0 || Get(track, "kind", "").AsString() != "instrument") track = document.Call("add_track", preset.Get("label"), "instrument").AsGodotDictionary();
            clip = document.Call("insert_source", Variant.From(empty), track["id"].AsString(), Math.Max(0, at), preset.Get("label")).AsGodotObject(); if (clip == null) { edits.cancel(session); return "Could not create the pattern clip."; }
            actor = document.Call("actor_for_clip", clip.Get("id")).AsGodotObject(); var selected = session.Get("selected_ids").AsGodotArray(); selected.Clear(); selected.Add(clip.Get("id")); session.Set("selected_track", track["id"].AsString());
        }
        var values = actor!.Get("values").AsGodotDictionary(); foreach (string key in new[] { "midi_tempos", "midi_tempo_scale", "midi_time_signatures", "midi_events", "midi_sustain", "drum_patterns", "drum_instances" }) values.Remove(new StringName(key));
        if (data.ContainsKey("drum_instances")) { values[new StringName("drum_patterns")] = Get(data, "drum_patterns", new Settings()).AsGodotDictionary().Duplicate(true); values[new StringName("drum_instances")] = data["drum_instances"].AsGodotArray().Duplicate(true); }
        foreach (string key in new[] { "midi_tempos", "midi_time_signatures", "midi_events" }) if (data.TryGetValue(key, out var raw)) values[key] = raw.AsGodotArray().Duplicate(true);
        if (data.ContainsKey("midi_tempos")) values[new StringName("midi_tempo_scale")] = Get(data, "midi_tempo_scale", 1.0).AsDouble(); if (data.ContainsKey("midi_sustain")) values[new StringName("midi_sustain")] = data["midi_sustain"].AsBool(); values[new StringName("source_bpm")] = sourceBpm;
        var currentConductor = document.Call("conductor").As<RefCounted>(); var meter = conductorOps.beat_info(currentConductor, conductorOps.seconds_to_beat(currentConductor, clip!.Get("start_time").AsDouble()));
        values[new StringName("source_meter")] = Get(data, "source_meter", new GArray { meter["numerator"].AsInt64(), meter["denominator"].AsInt64() }).AsGodotArray().Duplicate();
        values[new StringName("notes")] = Get(data, "notes", new GArray()).AsGodotArray().Duplicate(true);
        if (data.ContainsKey("instrument")) values[new StringName("instrument")] = data["instrument"].AsGodotDictionary().Duplicate(true); else if (!values.ContainsKey(new StringName("instrument"))) { using var instruments = new AudioInstrumentOperations(); values[new StringName("instrument")] = instruments.default_instrument("poly"); }
        values[new StringName("pattern_beats")] = Get(data, "pattern_beats", 4).AsDouble(); values[new StringName("step_settings")] = Get(data, "step_settings", new Settings()).AsGodotDictionary().Duplicate(true); values[new StringName("pattern_tags")] = Get(data, "tags", ArrayOf(preset.Get("tags"))).AsGodotArray().Duplicate(); values[new StringName("notes_dirty")] = true;
        edits.commit(session); session.EmitSignal("selection_changed"); return "";
    }
}
