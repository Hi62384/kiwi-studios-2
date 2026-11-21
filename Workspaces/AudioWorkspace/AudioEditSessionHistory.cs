using Godot;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioEditSessionOperations
{
    public long metadata_estimate(GodotObject document, long limit)
    {
        var actors = document.Get("actors").AsGodotArray();
        long total = System.Math.Min(limit, 1024L + actors.Count * 1024L + document.Get("clips").AsGodotArray().Count * 512L);
        long visits = 0;
        foreach (string key in new[] { "title", "tracks", "markers", "sections", "chords", "composer_settings", "master", "presets", "takes", "workspace_state", "output_path", "tempo_points", "meter_points", "scene_binding", "portable_media", "_portable_root" })
        {
            Estimate(document.Get(key), ref total, ref visits, System.Math.Max(1, limit), 0);
            if (total >= limit) return limit;
        }
        foreach (var raw in actors)
        {
            var actor = raw.AsGodotObject();
            if (actor == null) continue;
            foreach (string key in new[] { "id", "display_name", "parent_id", "section_id", "values", "animation_tracks" })
            {
                Estimate(actor.Get(key), ref total, ref visits, System.Math.Max(1, limit), 0);
                if (total >= limit) return limit;
            }
        }
        return total;
    }
    public void estimate_metadata_value(Variant value, GArray state, int depth)
    {
        long total = state[0].AsInt64(), visits = state[1].AsInt64();
        Estimate(value, ref total, ref visits, state[2].AsInt64(), depth);
        state[0] = total; state[1] = visits;
    }
    private static void Estimate(Variant value, ref long total, ref long visits, long limit, int depth)
    {
        if (total >= limit) return;
        if (++visits > 250000 || depth > 24) { total = limit; return; }
        long bytes = value.VariantType switch
        {
            Variant.Type.String or Variant.Type.StringName => 96L + value.AsString().Length * 4L,
            Variant.Type.Dictionary => 128L + value.AsGodotDictionary().Count * 96L,
            Variant.Type.Array => 64L + value.AsGodotArray().Count * 32L,
            Variant.Type.PackedStringArray => 64L + value.AsStringArray().Length * 32L,
            Variant.Type.PackedByteArray => 64L + value.AsByteArray().Length,
            Variant.Type.PackedInt32Array => 64L + value.AsInt32Array().Length * 4L,
            Variant.Type.PackedFloat32Array => 64L + value.AsFloat32Array().Length * 4L,
            Variant.Type.PackedInt64Array => 64L + value.AsInt64Array().Length * 8L,
            Variant.Type.PackedFloat64Array => 64L + value.AsFloat64Array().Length * 8L,
            Variant.Type.PackedVector2Array => 64L + value.AsVector2Array().Length * 16L,
            Variant.Type.PackedVector3Array => 64L + value.AsVector3Array().Length * 24L,
            Variant.Type.PackedVector4Array => 64L + value.AsVector4Array().Length * 32L,
            Variant.Type.PackedColorArray => 64L + value.AsColorArray().Length * 16L,
            Variant.Type.Object => 64,
            _ => 32
        };
        total = System.Math.Min(limit, total + bytes);
        if (total >= limit) return;
        if (value.VariantType == Variant.Type.Dictionary)
        {
            var dictionary = value.AsGodotDictionary();
            foreach (var key in dictionary.Keys)
            {
                Estimate(key, ref total, ref visits, limit, depth + 1);
                Estimate(dictionary[key], ref total, ref visits, limit, depth + 1);
                if (total >= limit) return;
            }
        }
        else if (value.VariantType == Variant.Type.Array)
            foreach (var entry in value.AsGodotArray()) { Estimate(entry, ref total, ref visits, limit, depth + 1); if (total >= limit) return; }
        else if (value.VariantType == Variant.Type.PackedStringArray)
            foreach (var entry in value.AsStringArray()) { Estimate(entry, ref total, ref visits, limit, depth + 1); if (total >= limit) return; }
    }
    public Settings source_footprint(GodotObject document, long metadataLimit)
    {
        var sources = new Settings { ["snapshot_metadata:" + document.GetInstanceId()] = metadata_estimate(document, metadataLimit) };
        void Add(Variant value)
        {
            if (value.VariantType != Variant.Type.Object || value.AsGodotObject() is not AudioStreamWav stream) return;
            sources[stream.GetInstanceId()] = stream.Data.LongLength;
        }
        foreach (var raw in document.Get("actors").AsGodotArray())
        {
            var actor = raw.AsGodotObject(); if (actor == null) continue;
            var values = actor.Get("values").AsGodotDictionary();
            foreach (string key in new[] { "audio", "original_audio" }) if (values.TryGetValue(new StringName(key), out var stream)) Add(stream);
            if (!values.TryGetValue(new StringName("instrument"), out var instrumentRaw)) continue;
            var instrument = instrumentRaw.AsGodotDictionary();
            if (instrument.TryGetValue("sample", out var sample)) Add(sample);
            if (instrument.TryGetValue("multisamples", out var mappings)) foreach (var mapping in mappings.AsGodotArray()) if (mapping.AsGodotDictionary().TryGetValue("sample", out sample)) Add(sample);
        }
        return sources;
    }
    private static void AddHistoryAction(RefCounted owner, UndoRedo history, string label, GodotObject before, GodotObject after)
    {
        var action = new AudioHistoryRestoreAction(owner, before, after);
        history.CreateAction(label);
        history.AddDoMethod(new Callable(action, nameof(AudioHistoryRestoreAction.restore_after)));
        history.AddUndoMethod(new Callable(action, nameof(AudioHistoryRestoreAction.restore_before)));
        history.AddDoReference(action);
        history.CommitAction(false);
    }
    public void commit(RefCounted owner)
    {
        var previousRaw = owner.Get("_before");
        if (previousRaw.VariantType == Variant.Type.Nil) return;
        var previous = previousRaw.AsGodotObject();
        owner.Set("_before", default(Variant));
        var current = Document(owner).Call("snapshot").AsGodotObject();
        var history = owner.Get("history").As<UndoRedo>();
        var footprints = owner.Get("_history_footprints").AsGodotArray();
        var actions = owner.Get("_history_actions").AsGodotArray();
        int kept = history.GetCurrentAction() + 1;
        if (kept < footprints.Count) { footprints.Resize(System.Math.Max(0, kept)); actions.Resize(System.Math.Max(0, kept)); }
        long budget = owner.Get("history_byte_budget").AsInt64();
        long limit = System.Math.Max(1, budget + 1);
        var footprint = source_footprint(previous, limit);
        footprint.Merge(source_footprint(current, limit), true);
        footprints.Add(footprint);
        string label = owner.Get("_label").AsString();
        actions.Add(new Settings { ["label"] = label, ["before"] = previous, ["after"] = current });
        history.MaxSteps = System.Math.Max(1, owner.Get("history_limit").AsInt32());
        AddHistoryAction(owner, history, label, previous, current);
        while (footprints.Count > history.GetHistoryCount()) { footprints.RemoveAt(0); actions.RemoveAt(0); }
        bool trimmed = false;
        while (footprints.Count > 1)
        {
            var unique = new Settings();
            foreach (var raw in footprints) unique.Merge(raw.AsGodotDictionary(), true);
            long bytes = 0;
            foreach (var size in unique.Values) bytes += size.AsInt64();
            if (bytes <= budget) break;
            footprints.RemoveAt(0); actions.RemoveAt(0);
            owner.Set("history_pruned_actions", owner.Get("history_pruned_actions").AsInt64() + 1);
            trimmed = true;
        }
        if (trimmed)
        {
            history.ClearHistory(false);
            foreach (var raw in actions)
            {
                var entry = raw.AsGodotDictionary();
                AddHistoryAction(owner, history, entry["label"].AsString(), entry["before"].AsGodotObject(), entry["after"].AsGodotObject());
            }
        }
        owner.Set("dirty", true);
        owner.Set("revision", owner.Get("revision").AsInt64() + 1);
        owner.EmitSignal("changed");
    }
}
