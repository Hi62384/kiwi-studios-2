using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioEditSessionOperations
{
    public void change_tempo(RefCounted owner, double bpm)
    {
        if (!double.IsFinite(bpm)) return;
        var document = Document(owner);
        set_conductor(owner, Math.Clamp(bpm, 20, 400), document.Get("time_signature").AsVector2I(), document.Get("tempo_points").AsGodotArray(), document.Get("meter_points").AsGodotArray());
    }
    public void change_meter(RefCounted owner, Vector2I signature)
    {
        var document = Document(owner);
        set_conductor(owner, document.Get("tempo").AsDouble(), signature, document.Get("tempo_points").AsGodotArray(), document.Get("meter_points").AsGodotArray());
    }
    public string retime_note_sources(RefCounted owner, double bpm)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return "Finish the current edit before retiming sources.";
        using var conductor = new AudioConductorOperations(); using var maps = new AudioTempoMapOperations();
        if (!conductor.number(bpm, 20, 400)) return "Choose 20–400 BPM.";
        var document = Document(owner); string problem = document.Call("midi_timing_error").AsString();
        if (problem.Length > 0) return problem;
        double oldTempo = document.Get("tempo").AsDouble(); var signature = document.Get("time_signature").AsVector2I(); var meters = document.Get("meter_points").AsGodotArray();
        problem = conductor.validate(oldTempo, signature, document.Get("tempo_points"), meters);
        if (problem.Length > 0) return problem;
        if (bpm == oldTempo) return "";
        double ratio = oldTempo / bpm;
        var tempos = document.Get("tempo_points").AsGodotArray().Duplicate(true);
        foreach (var raw in tempos) { var point = raw.AsGodotDictionary(); point["bpm"] = point["bpm"].AsDouble() / ratio; }
        if (conductor.validate(bpm, signature, tempos, meters).Length > 0) return "Uniform retiming would put a conductor point outside 20–400 BPM.";
        var operations = new System.Collections.Generic.List<(GodotObject Clip, Settings Values, bool Mapped, double Bpm, double Scale, double Pending)>();
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray();
        for (int i = 0; i < clips.Count; ++i)
        {
            var clip = clips[i].AsGodotObject(); var actor = actors[i].AsGodotObject();
            if (!is_note_source(actor) || !can_edit(owner, clip.Get("id").AsString()) || document.Call("track_for_clip", clip.Get("id")).AsGodotDictionary().ContainsKey("frozen_track")) continue;
            var values = actor.Get("values").AsGodotDictionary(); bool mapped = values.ContainsKey(new StringName("midi_tempos"));
            double sourceBpm = note_source_tempo(actor, document) / ratio, scale = Setting(values, "midi_tempo_scale", 1.0).AsDouble() * ratio, pending = Setting(values, "notes_source_scale", 1.0).AsDouble() * ratio;
            bool ValidScale(double v) => double.IsFinite(v) && v >= .000001 && v <= 1000000;
            if (!ValidScale(pending)) return "The pending source-window scale is outside the supported range. Render the current notes before retiming again.";
            if (mapped && !ValidScale(scale)) return "A MIDI source scale would leave the supported range.";
            if (!mapped && !conductor.number(sourceBpm, 20, 400)) return "A note source would leave the supported 20–400 BPM range.";
            using var timing = KiwiAudioTempoMap.create(Setting(values, "midi_tempos", new GArray()),mapped ? note_source_tempo(actor, document) : sourceBpm,mapped ? scale : 1.0);
            double lastBeat = Setting(values, "pattern_beats", 0.0).AsDouble();
            foreach (var raw in Setting(values, "notes", new GArray()).AsGodotArray()) { var note = raw.AsGodotDictionary(); lastBeat = Math.Max(lastBeat, Setting(note, "start", 0).AsDouble() + Setting(note, "duration", .25).AsDouble()); }
            if (timing.Get("error").AsString().Length > 0 || maps.beat_to_seconds(timing, lastBeat) > 300) return "Uniform retiming would exceed the 300-second editable note-source limit.";
            operations.Add((clip, values, mapped, sourceBpm, scale, pending));
        }
        double arrangementBpm = document.Call("arrangement_tempo").AsDouble() / ratio;
        bool sections = document.Get("sections").AsGodotArray().Count > 0;
        if (sections && !conductor.number(arrangementBpm, 20, 400)) return "The generated arrangement would leave the supported tempo range.";
        begin(owner, "Uniformly retime editable note sources");
        if (document.Get("note_base_tempo").AsDouble() == 0) document.Set("note_base_tempo", oldTempo);
        if (document.Get("note_base_meter").AsVector2I() == Vector2I.Zero) document.Set("note_base_meter", signature);
        foreach (var operation in operations)
        {
            operation.Clip.Set("start_time", operation.Clip.Get("start_time").AsDouble() * ratio); operation.Clip.Set("duration", operation.Clip.Get("duration").AsDouble() * ratio);
            operation.Values[new StringName(operation.Mapped ? "midi_tempo_scale" : "source_bpm")] = operation.Mapped ? operation.Scale : operation.Bpm;
            operation.Values[new StringName("notes_source_scale")] = operation.Pending; operation.Values[new StringName("notes_dirty")] = true;
        }
        if (sections) document.Get("composer_settings").AsGodotDictionary()["tempo"] = arrangementBpm;
        document.Set("tempo", bpm); var target = document.Get("tempo_points").AsGodotArray(); target.Clear(); foreach (var point in tempos) target.Add(point);
        commit(owner); return "";
    }
    public string note_signature(GodotObject actor, GodotObject document)
    {
        var values = actor.Get("values").AsGodotDictionary(); var track = document.Call("track_for_id", Setting(values, "track_id", "").AsString()).AsGodotDictionary(); bool sustain = Setting(values, "midi_sustain", false).AsBool();
        return GD.VarToStr(new GArray { Setting(values, "notes", new GArray()), Setting(values, "drum_patterns", new Settings()), Setting(values, "drum_instances", new GArray()), Setting(values, "instrument", Setting(track, "instrument", new Settings { ["id"] = "poly" })), note_source_tempo(actor, document), Setting(values, "pattern_beats", 0), Setting(values, "step_settings", new Settings()), Setting(values, "midi_tempos", new GArray()), Setting(values, "midi_tempo_scale", 1.0), sustain, sustain ? Setting(values, "midi_events", new GArray()) : new GArray() }).Sha256Text();
    }
    public AudioStreamWav? render_note_source(GArray notes, Settings instrument, double bpm, Settings stepSettings, double patternBeats, GArray tempos, double tempoScale, RefCounted? job, GArray sustainEvents)
    {
        using var maps = new AudioTempoMapOperations();
        using var timing = KiwiAudioTempoMap.create(tempos,bpm,tempoScale);
        if (timing.Get("error").AsString().Length > 0) return null;
        double seconds = patternBeats > 0 ? maps.beat_to_seconds(timing, patternBeats) : 0;
        if (seconds > 300) return null;
        Variant jobValue = job == null ? default : Variant.From(job);
        if (sustainEvents.Count > 0)
        {
            if (maps.validate_channel_events(sustainEvents).Length > 0) return null;
            notes = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_midi.gd").Call("sustain_copy", notes, sustainEvents, patternBeats, jobValue).AsGodotArray();
            if (job != null && job.Call("is_cancelled").AsBool()) return null;
        }
        var renderedNotes = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_step_controls.gd").Call("render_copy", notes, stepSettings, instrument);
        var stream = GD.Load<CSharpScript>("res://Workspaces/AudioWorkspace/KiwiAudioInstruments.cs").Call("render_notes", renderedNotes, instrument, bpm, 44100, jobValue, tempos, tempoScale).As<AudioStreamWav>();
        if (stream != null && patternBeats > 0) { using var cache = new AudioSourceCacheOperations(); return cache.fit_pattern(stream, seconds); }
        return stream;
    }
    public string render_current_notes(GodotObject document, RefCounted? job, GArray clipIds)
    {
        string error = document.Call("midi_timing_error").AsString(); if (error.Length > 0) return error;
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray();
        for (int i = 0; i < clips.Count; ++i)
        {
            var clip = clips[i].AsGodotObject(); if (clipIds.Count > 0 && !clipIds.Contains(clip.Get("id"))) continue;
            var actor = actors[i].AsGodotObject(); if (!is_note_source(actor)) continue;
            var track = document.Call("track_for_clip", clip.Get("id")).AsGodotDictionary(); if (track.ContainsKey("frozen_track")) continue;
            var values = actor.Get("values").AsGodotDictionary(); string signature = note_signature(actor, document);
            if (!Setting(values, "notes_dirty", false).AsBool() && Setting(values, "rendered_signature", "").AsString() == signature) continue;
            if (job != null && job.Call("is_cancelled").AsBool()) return "Cancelled.";
            var instrument = Setting(values, "instrument", Setting(track, "instrument", new Settings { ["id"] = "poly" })).AsGodotDictionary().Duplicate(true);
            var notes = Setting(values, "notes", new GArray()).AsGodotArray().Duplicate(true);
            if (values.ContainsKey(new StringName("drum_instances")))
            {
                var linked = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd");
                error = linked.Call("validate", Setting(values, "drum_patterns", new Settings()), Setting(values, "drum_instances")).AsString(); if (error.Length > 0) return error;
                notes = linked.Call("notes", actor).AsGodotArray();
            }
            var sustain = Setting(values, "midi_sustain", false).AsBool() ? Setting(values, "midi_events", new GArray()).AsGodotArray() : new GArray();
            var stream = render_note_source(notes, instrument, note_source_tempo(actor, document), Setting(values, "step_settings", new Settings()).AsGodotDictionary(), Setting(values, "pattern_beats", 0).AsDouble(), Setting(values, "midi_tempos", new GArray()).AsGodotArray(), Setting(values, "midi_tempo_scale", 1.0).AsDouble(), job, sustain);
            if (stream == null) return "The current instrument notes could not be rendered. Check required samples and the 300-second source limit (including note releases). No output was saved.";
            apply_note_render(clip, actor, stream, signature);
        }
        return "";
    }
}
