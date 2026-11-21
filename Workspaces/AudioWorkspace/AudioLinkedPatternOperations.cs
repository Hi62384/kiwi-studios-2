using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioLinkedPatternOperations : RefCounted
{
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var found) ? found : fallback;
    private static string Id() { using var crypto = new Crypto(); return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant(); }
    public string validate(Variant definitionsRaw, Variant instancesRaw)
    {
        if (definitionsRaw.VariantType != Variant.Type.Dictionary || instancesRaw.VariantType != Variant.Type.Array) return "Linked drums support 256 definitions and 512 instances.";
        var definitions = definitionsRaw.AsGodotDictionary(); var instances = instancesRaw.AsGodotArray();
        if (definitions.Count > 256 || instances.Count > 512) return "Linked drums support 256 definitions and 512 instances.";
        using var conductor = new AudioConductorOperations(); var costs = new System.Collections.Generic.Dictionary<string, int>();
        foreach (var id in definitions.Keys)
        {
            var raw = definitions[id];
            if (id.VariantType != Variant.Type.String || id.AsString().Length > 128 || raw.VariantType != Variant.Type.Dictionary) return "Invalid linked drum definition.";
            var pattern = raw.AsGodotDictionary();
            if (!conductor.number(Get(pattern, "steps", 16), 1, 256) || !conductor.number(Get(pattern, "length", 4), .0625, 64) || !conductor.number(Get(pattern, "swing", 0), -.45, .45)) return "Invalid linked drum dimensions.";
            var lanes = Get(pattern, "lanes", new GArray()); if (lanes.VariantType != Variant.Type.Array || lanes.AsGodotArray().Count > 128) return "Invalid linked drum lanes.";
            int cost = 0;
            foreach (var laneRaw in lanes.AsGodotArray())
            {
                if (laneRaw.VariantType != Variant.Type.Dictionary) return "Invalid linked drum lane.";
                var lane = laneRaw.AsGodotDictionary(); var values = Get(lane, "values", new GArray());
                if (!conductor.number(Get(lane, "pitch", 36), 0, 127) || values.VariantType != Variant.Type.Array || values.AsGodotArray().Count > 256) return "Invalid linked drum lane.";
                foreach (var cell in values.AsGodotArray())
                {
                    if (cell.VariantType == Variant.Type.Dictionary)
                    {
                        var step = cell.AsGodotDictionary();
                        if (!conductor.number(Get(step, "velocity", .8), 0, 1) || !conductor.number(Get(step, "probability", 1), 0, 1) || !conductor.number(Get(step, "ratchets", 1), 1, 8)) return "Invalid linked drum step.";
                        if (Get(step, "enabled", true).AsBool() && Get(step, "velocity", .8).AsDouble() > 0) cost += (int)Get(step, "ratchets", 1).AsDouble();
                    }
                    else if (conductor.number(cell, 0, 1)) { if (cell.AsDouble() > 0) ++cost; }
                    else return "Invalid linked drum step.";
                }
            }
            costs[id.AsString()] = cost;
        }
        int total = 0; var seen = new System.Collections.Generic.HashSet<string>();
        foreach (var raw in instances)
        {
            if (raw.VariantType != Variant.Type.Dictionary) return "Invalid linked drum instance.";
            var instance = raw.AsGodotDictionary(); string id = Get(instance, "id", "").AsString(), patternId = Get(instance, "pattern_id", "").AsString();
            if (id.Length == 0 || id.Length > 128 || !seen.Add(id) || !definitions.ContainsKey(patternId) || !conductor.number(Get(instance, "start", 0), 0, 2048) || !conductor.number(Get(instance, "length", 4), .001, 64)) return "Invalid linked drum instance reference or timing.";
            total += costs[patternId]; if (total > 8192) return "Linked drum expansion exceeds the 8192-note source budget.";
        }
        return "";
    }
    public Settings from_part(Settings part, GArray meter)
    {
        var definitions = new Settings(); var instances = new GArray(); var byContent = new System.Collections.Generic.Dictionary<string, string>();
        double span = meter[0].AsDouble() * 4 / meter[1].AsDouble();
        foreach (var raw in Get(part, "patterns", new GArray()).AsGodotArray())
        {
            var source = raw.AsGodotDictionary(); var pattern = source.Duplicate(true);
            foreach (string key in new[] { "id", "start", "section_id" }) pattern.Remove(key);
            string hash = GD.VarToStr(pattern).Sha256Text();
            if (!byContent.TryGetValue(hash, out var id)) { id = Id(); definitions[id] = pattern; byContent[hash] = id; }
            double start = Get(source, "start", 0).AsDouble();
            string sourceId = Get(source, "id", "").AsString();
            instances.Add(new Settings { ["id"] = Get(source, "id", Id()).AsString(), ["pattern_id"] = id, ["start"] = start, ["length"] = Math.Min(span, Math.Max(.001, part["pattern_beats"].AsDouble() - start)), ["section_id"] = Get(source, "section_id", "").AsString(), ["seed"] = (long)unchecked((uint)GD.Hash(sourceId)) });
        }
        return new Settings { ["definitions"] = definitions, ["instances"] = instances };
    }
    public GArray notes(GodotObject actor)
    {
        var values = actor.Get("values").AsGodotDictionary();
        if (!values.ContainsKey(new StringName("drum_instances"))) return Get(values, "notes", new GArray()).AsGodotArray().Duplicate(true);
        var result = new System.Collections.Generic.List<Settings>(); var definitions = Get(values, "drum_patterns", new Settings()).AsGodotDictionary();
        var composer = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_composer.gd");
        foreach (var raw in Get(values, "drum_instances", new GArray()).AsGodotArray())
        {
            var instance = raw.AsGodotDictionary(); string id = Get(instance, "pattern_id", "").AsString(); if (!definitions.TryGetValue(id, out var definition)) continue;
            var pattern = definition.AsGodotDictionary(); double span = Get(instance, "length", 4).AsDouble(), length = Math.Max(.0625, Get(pattern, "length", 4).AsDouble());
            foreach (var sourceRaw in composer.Call("pattern_notes", pattern, 1, Get(instance, "seed", 1).AsInt64()).AsGodotArray())
            {
                var source = sourceRaw.AsGodotDictionary(); var note = source.Duplicate(true); double local = note["start"].AsDouble() / length * span;
                note["start"] = instance["start"].AsDouble() + local; note["duration"] = Math.Min(note["duration"].AsDouble(), span - local); note["id"] = instance["id"].AsString() + "_" + source["id"].AsString(); note["section_id"] = Get(instance, "section_id", "").AsString(); result.Add(note);
            }
        }
        result.Sort((a, b) => a["start"].AsDouble().CompareTo(b["start"].AsDouble())); var output = new GArray(); foreach (var note in result) output.Add(note); return output;
    }
    public void sync(GodotObject actor) { var values = actor.Get("values").AsGodotDictionary(); if (values.ContainsKey(new StringName("drum_instances"))) values[new StringName("notes")] = notes(actor); }
    public void detach(GodotObject actor) { sync(actor); var values = actor.Get("values").AsGodotDictionary(); values.Remove(new StringName("drum_patterns")); values.Remove(new StringName("drum_instances")); }
}
