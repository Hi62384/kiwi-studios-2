using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioAutomationLaneOperations : RefCounted
{
    private readonly Settings _definitions = new();
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(new StringName(key), out var found) ? found : fallback;
    public Settings effect_definition(string type) { if (!_definitions.TryGetValue(type, out var raw)) { using var effects = new AudioEffectsOperations(); var definition = effects.definition(type); _definitions[type] = definition; return definition; } return raw.AsGodotDictionary(); }
    public bool is_lane(Settings track) => Get(track, "kind", "").AsString() == "automation";
    public string key(Settings target) => GD.VarToStr(new GArray { Get(target, "owner_kind", ""), Get(target, "owner_id", ""), Get(target, "effect_id", ""), Get(target, "parameter", "") });
    public Settings resolve(GodotObject document, Settings target)
    {
        string kind = Get(target, "owner_kind", "").AsString(), id = Get(target, "owner_id", "").AsString(), label; double offset = 0, length = Math.Max(1, document.Call("duration").AsDouble()); bool locked = false; Settings owner;
        switch (kind)
        {
            case "master": owner = document.Get("master").AsGodotDictionary(); label = "Master"; break;
            case "track": owner = document.Call("track_for_id", id).AsGodotDictionary(); if (owner.Count == 0 || is_lane(owner)) return new Settings(); label = Get(owner, "name", "Track").AsString(); locked = Get(owner, "locked", false).AsBool(); break;
            case "clip": var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject(); if (clip == null || actor == null) return new Settings(); owner = actor.Get("values").AsGodotDictionary(); label = actor.Get("display_name").AsString(); offset = clip.Get("start_time").AsDouble(); length = clip.Get("duration").AsDouble(); locked = Get(document.Call("track_for_clip", id).AsGodotDictionary(), "locked", false).AsBool(); break;
            default: return new Settings();
        }
        string parameter = Get(target, "parameter", "").AsString(), effectId = Get(target, "effect_id", "").AsString(); var definition = new Settings();
        if (effectId.Length > 0)
        {
            Settings? found = null; foreach (var raw in Get(owner, "effects", new GArray()).AsGodotArray()) { var effect = raw.AsGodotDictionary(); if (Get(effect, "id", "").AsString() == effectId) { found = effect; break; } } if (found == null || found.Count == 0) return new Settings(); owner = found; string type = Get(owner, "type", "").AsString(); using var effects = new AudioEffectsOperations(); if (!effects.automation_commands(type).ContainsKey(parameter)) return new Settings();
            var effectDefinition = effect_definition(type); foreach (var raw in Get(effectDefinition, "parameters", new GArray()).AsGodotArray()) { var field = raw.AsGodotDictionary(); if (Get(field, "id", "").AsString() == parameter) { definition = field; break; } } if (definition.Count == 0) return new Settings(); label += " / " + Get(effectDefinition, "label", type).AsString();
        }
        else
        {
            if (parameter != "volume_db" && !(parameter == "pan" && kind != "master") && !(parameter == "pitch" && kind == "clip")) return new Settings();
            definition = new Settings { ["min"] = parameter == "pitch" ? .25 : parameter == "pan" ? -1.0 : -60.0, ["max"] = parameter == "pitch" ? 4.0 : parameter == "pan" ? 1.0 : 12.0 };
        }
        double fallback = Get(Get(owner, "parameters", owner).AsGodotDictionary(), parameter, parameter == "pitch" ? 1.0 : 0.0).AsDouble();
        return new Settings { ["target"] = target.Duplicate(true), ["owner"] = owner, ["parameter"] = parameter, ["label"] = label + " / " + parameter, ["offset"] = offset, ["duration"] = length, ["minimum"] = Get(definition, "min", -60).AsDouble(), ["maximum"] = Get(definition, "max", 12).AsDouble(), ["fallback"] = fallback, ["locked"] = locked };
    }
    public Settings lane_info(GodotObject document, string laneId) { var lane = document.Call("track_for_id", laneId).AsGodotDictionary(); var target = Get(lane, "automation_target", new Settings()); return is_lane(lane) && target.VariantType == Variant.Type.Dictionary ? resolve(document, target.AsGodotDictionary()) : new Settings(); }
    public bool editable(GodotObject document, string laneId) { var info = lane_info(document, laneId); return info.Count > 0 && !info["locked"].AsBool() && !Get(document.Call("track_for_id", laneId).AsGodotDictionary(), "locked", false).AsBool(); }
    public GArray points(Settings info) { if (info.Count == 0) return new GArray(); var curves = Get(info["owner"].AsGodotDictionary(), "automation", new Settings()).AsGodotDictionary(); return Get(curves, info["parameter"].AsString(), new GArray()).AsGodotArray(); }
    public double value(GArray points, double time, double fallback)
    {
        if (points.Count == 0) return fallback; if (time <= points[0].AsGodotDictionary()["time"].AsDouble()) return points[0].AsGodotDictionary()["value"].AsDouble(); int low = 0, high = points.Count - 1;
        while (low < high) { int middle = low + (high - low + 1) / 2; if (points[middle].AsGodotDictionary()["time"].AsDouble() <= time) low = middle; else high = middle - 1; }
        if (low + 1 >= points.Count) return points[points.Count - 1].AsGodotDictionary()["value"].AsDouble(); using var effects = new AudioEffectsOperations(); return effects.automation_value(new GArray { points[low], points[low + 1] }, time, fallback);
    }
    public Godot.Collections.Array<Settings> options(GodotObject document)
    {
        var owners = new GArray { new Settings { ["owner_kind"] = "master", ["owner_id"] = "" } }; foreach (var raw in document.Get("tracks").AsGodotArray()) { var track = raw.AsGodotDictionary(); if (!is_lane(track)) owners.Add(new Settings { ["owner_kind"] = "track", ["owner_id"] = track["id"].AsString() }); } foreach (var raw in document.Get("clips").AsGodotArray()) owners.Add(new Settings { ["owner_kind"] = "clip", ["owner_id"] = raw.AsGodotObject().Get("id") });
        var output = new Godot.Collections.Array<Settings>(); using var effects = new AudioEffectsOperations();
        foreach (var raw in owners)
        {
            var target = raw.AsGodotDictionary(); var basis = target.Duplicate(true); basis["parameter"] = "volume_db"; var info = resolve(document, basis); if (info.Count == 0) continue; string kind = target["owner_kind"].AsString(); string[] parameters = kind == "master" ? new[] { "volume_db" } : kind == "clip" ? new[] { "volume_db", "pan", "pitch" } : new[] { "volume_db", "pan" };
            foreach (string parameter in parameters) { var item = target.Duplicate(true); item["parameter"] = parameter; item["effect_id"] = ""; output.Add(resolve(document, item)); }
            foreach (var effectRaw in Get(info["owner"].AsGodotDictionary(), "effects", new GArray()).AsGodotArray())
            {
                var effect = effectRaw.AsGodotDictionary(); string type = Get(effect, "type", "").AsString(); var supported = effects.automation_commands(type);
                foreach (var fieldRaw in Get(effect_definition(type), "parameters", new GArray()).AsGodotArray()) { var field = fieldRaw.AsGodotDictionary(); string parameter = Get(field, "id", "").AsString(); if (!supported.ContainsKey(parameter)) continue; var item = target.Duplicate(true); item["parameter"] = parameter; item["effect_id"] = Get(effect, "id", "").AsString(); var resolved = resolve(document, item); if (resolved.Count > 0) output.Add(resolved); }
            }
        }
        return output;
    }
    public string binding_error(GodotObject document, string laneId)
    {
        var lane = document.Call("track_for_id", laneId).AsGodotDictionary(); if (lane.Count == 0) return "The automation lane no longer exists.";
        foreach (var raw in document.Get("actors").AsGodotArray()) if (Get(raw.AsGodotObject().Get("values").AsGodotDictionary(), "track_id", "").AsString() == laneId) return "This legacy automation track contains audio clips. Move them to an audio track, or convert this lane back to audio first.";
        if (Get(lane, "output", "").AsString().Length > 0 || Get(lane, "sends", new GArray()).AsGodotArray().Count > 0) return "This legacy track has audio routing. Convert it back to an audio track to preserve that routing.";
        if (Get(lane, "effects", new GArray()).AsGodotArray().Count > 0 || Get(lane, "automation", new Settings()).AsGodotDictionary().Count > 0 || Get(lane, "solo", false).AsBool() || Get(lane, "mute", false).AsBool()) return "This legacy track has its own processing or mute/solo state. Convert it back to an audio track before creating a linked lane.";
        foreach (var raw in document.Get("tracks").AsGodotArray()) { var other = raw.AsGodotDictionary(); if (Get(other, "output", "").AsString() == laneId) return "Audio is routed into this legacy track. Convert it back to an audio track before creating a linked lane."; foreach (var send in Get(other, "sends", new GArray()).AsGodotArray()) if (Get(send.AsGodotDictionary(), "target", "").AsString() == laneId) return "An audio send targets this legacy track. Convert it back to an audio track before creating a linked lane."; }
        return "";
    }
}
