using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthPhysicsOperations : RefCounted
{
    private readonly SurfaceGrowthGeometry _geometry = new();
    private readonly SurfaceGrowthSettings _settings = new();
    private static Settings Dict(GodotObject value, string key) => value.Get(key).AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Settings Prototype(GodotObject controller, string id) => Dict(controller, "prototypes")[id].AsGodotDictionary();
    private static GodotObject Actor(GodotObject controller, string id) => Prototype(controller, id)["actor"].AsGodotObject();
    private static string RootId(Settings root) => root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture);
    public Resource? data(GodotObject actor)
    {
        var component = Get(Dict(actor, "values"), "model_component_data").As<Resource>();
        if (component == null) return null; var script = component.GetScript().As<Script>();
        while (script != null) { if ((script.ResourcePath=="res://Workspaces/ModelWorkspace/model_component.gd"||script.ResourcePath=="res://Workspaces/ModelWorkspace/KiwiModelComponent.cs")) return component.Get("growth").As<Resource>(); script = script.GetBaseScript(); } return null;
    }
    public Vector3[] points(GodotObject controller, string id, double time)
    {
        var actor = Actor(controller, id); var growth = data(actor)!; string rigId = Get(Dict(actor, "values"), "model_skeleton_actor", "").AsString();
        var source = growth.Get("source_points").AsVector3Array(); var weights = growth.Get("source_weights").AsGodotArray(); var skin = growth.Get("source_skin").As<Skin>();
        if (skin == null || weights.Count == 0 || rigId.Length == 0) return source;
        var rig = controller.Get("_model").As<RefCounted>().Call("actor_for_id", rigId).AsGodotObject(); if (rig == null) return source;
        var inverse = controller.Call("animated_world", rigId, time, true).AsTransform3D().AffineInverse(); var bones = Get(Dict(rig, "values"), "rig_bones", new GArray()).AsGodotArray(); var matrices = new Transform3D[skin.GetBindCount()];
        for (int i = 0; i < matrices.Length; i++)
        {
            int index = skin.GetBindBone(i); string name = skin.GetBindName(i).ToString(); if (name.Length == 0 && index >= 0 && index < bones.Count) name = bones[index].AsGodotDictionary()["name"].AsString();
            matrices[i] = inverse * controller.Call("bone_world", rigId, name, time).AsTransform3D() * skin.GetBindPose(i);
        }
        var result = new Vector3[source.Length];
        for (int i = 0; i < result.Length; i++)
        {
            double total = 0; Vector3 point = Vector3.Zero;
            foreach (var pair in weights[i].AsGodotDictionary()) { int bone = pair.Key.AsInt32(); if (bone >= 0 && bone < matrices.Length) { float weight = pair.Value.AsSingle(); point += matrices[bone] * source[i] * weight; total += weight; } }
            result[i] = total > .00001 ? point / (float)total : source[i];
        }
        return result;
    }
    public Transform3D world(GodotObject controller, string id, double time)
    {
        var actor = Actor(controller, id); var growth = data(actor)!; string rigId = Get(Dict(actor, "values"), "model_skeleton_actor", "").AsString(); var rig = controller.Get("_model").As<RefCounted>().Call("actor_for_id", rigId).AsGodotObject();
        if (rig != null)
        {
            var bones = Get(Dict(rig, "values"), "rig_bones", new GArray()).AsGodotArray(); int bone = growth.Get("rigid_bone").AsInt32();
            if (bone >= 0 && bone < bones.Count) return controller.Call("bone_world", rigId, bones[bone].AsGodotDictionary()["name"], time).AsTransform3D() * growth.Get("rigid_offset").AsTransform3D();
            if (growth.Get("source_skin").As<Skin>() != null) return controller.Call("animated_world", rigId, time, true).AsTransform3D();
        }
        return controller.Call("animated_world", id, time, true).AsTransform3D();
    }
    public void initialize(GodotObject controller, string id, Settings state, Settings config, double time)
    {
        var prototype = Prototype(controller, id); var growth = data(prototype["actor"].AsGodotObject()); if (growth == null) return;
        var roots = growth.Get("roots").AsGodotArray(); if (roots.Count == 0) return; var controls = new Godot.Collections.Array<Settings>(); var weights = new Settings(); var authored = new HashSet<string>(StringComparer.Ordinal);
        var rootLookup = new Dictionary<long, Settings>(); foreach (var row in roots) { var root = row.AsGodotDictionary(); rootLookup[root["id"].AsInt64()] = root; }
        foreach (var pair in Dict(growth, "guides"))
        {
            if (rootLookup.TryGetValue(pair.Value.AsGodotDictionary()["root"].AsInt64(), out var root)) { controls.Add(new Settings { ["id"] = pair.Key, ["root"] = root }); authored.Add(pair.Key.AsString()); }
            if (controls.Count >= 128) break;
        }
        if (controls.Count == 0)
        {
            int count = Math.Min(roots.Count, Math.Min(128, Math.Max(1, Get(config, "particles", 64).AsInt32())));
            for (int index = 0; index < count; index++) { var root = roots[index * roots.Count / count].AsGodotDictionary(); controls.Add(new Settings { ["id"] = "auto-" + RootId(root), ["root"] = root }); }
        }
        var controlPositions = controls.Select(control => (Position: control["root"].AsGodotDictionary()["position"].AsVector3(), Id: control["id"].AsString())).ToArray(); _settings.prepare_regions(growth);
        foreach (var row in roots)
        {
            var root = row.AsGodotDictionary(); var edit = _geometry.PreparedStyle(growth, root); var chosen = Get(edit, "guide_weights", new Settings()).AsGodotDictionary().Duplicate(); string guide = Get(edit, "guide", "").AsString();
            if (chosen.Count == 0 && guide.Length > 0) chosen[guide] = 1.0; foreach (var key in chosen.Keys.ToArray()) if (!authored.Contains(key.AsString())) chosen.Remove(key);
            if (chosen.Count == 0)
            {
                Vector3 position = root["position"].AsVector3(); var nearby = new (float Distance, string Id)[4]; int size = 0;
                foreach (var control in controlPositions)
                {
                    float distance = position.DistanceSquaredTo(control.Position); int at = size; while (at > 0 && nearby[at - 1].Distance > distance) at--;
                    if (at >= 4) continue; for (int i = Math.Min(size, 3); i > at; i--) nearby[i] = nearby[i - 1]; nearby[at] = (distance, control.Id); size = Math.Min(4, size + 1);
                }
                for (int i = 0; i < size; i++) chosen[nearby[i].Id] = 1.0 / Math.Max(.0001, nearby[i].Distance);
            }
            weights[RootId(root)] = chosen;
        }
        var targets = new List<Vector3>(); var edges = new GArray(); var source = points(controller, id, time); var transform = world(controller, id, time);
        foreach (var control in controls)
        {
            var root = control["root"].AsGodotDictionary(); var curve = _geometry.curve(growth, root, 8); int first = targets.Count; control["first"] = first; control["count"] = curve.Length; var frame = transform * _geometry.point_frame(growth, root, source);
            foreach (Vector3 point in curve) targets.Add(frame * point);
            for (int i = 0; i < curve.Length - 1; i++) edges.Add(new GArray { first + i, first + i + 1, targets[first + i].DistanceTo(targets[first + i + 1]), false });
            for (int i = 0; i < curve.Length - 2; i++) edges.Add(new GArray { first + i, first + i + 2, targets[first + i].DistanceTo(targets[first + i + 2]), true });
        }
        var buffer = targets.ToArray(); prototype["growth"] = new Settings { ["controls"] = controls, ["weights"] = weights, ["binding"] = unchecked((uint)GD.Hash(new GArray { controls, weights })) };
        prototype["graph"] = new Settings { ["rest"] = buffer, ["local"] = Array.Empty<Vector3>(), ["edges"] = edges, ["error"] = "", ["bindings"] = new GArray() };
        state["points"] = buffer; state["velocities"] = new Vector3[buffer.Length]; state["pose"] = transform;
    }
    public Settings targets(GodotObject controller, string id, double time)
    {
        var prototype = Prototype(controller, id); var growth = data(prototype["actor"].AsGodotObject())!; var result = new Settings(); var source = points(controller, id, time); var transform = world(controller, id, time);
        foreach (var row in Get(Get(prototype, "growth", new Settings()).AsGodotDictionary(), "controls", new GArray()).AsGodotArray())
        {
            var control = row.AsGodotDictionary(); var root = control["root"].AsGodotDictionary(); var frame = transform * _geometry.point_frame(growth, root, source); var curve = _geometry.curve(growth, root, 8);
            for (int i = 0; i < Math.Min(control["count"].AsInt32(), curve.Length); i++) result[control["first"].AsInt32() + i] = frame * curve[i];
        }
        return result;
    }
    public Settings pins(GodotObject controller, string id, double time)
    {
        var desired = targets(controller, id, time); var result = new Settings();
        foreach (var row in Get(Get(Prototype(controller, id), "growth", new Settings()).AsGodotDictionary(), "controls", new GArray()).AsGodotArray()) { int first = row.AsGodotDictionary()["first"].AsInt32(); result[first] = desired[first]; } return result;
    }
}
