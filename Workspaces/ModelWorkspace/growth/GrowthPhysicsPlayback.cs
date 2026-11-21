using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthPhysicsOperations
{
    public void apply(GodotObject controller, string id, Settings state, Settings config, double time)
    {
        var prototype = Prototype(controller, id); var runtime = controller.Call("_runtime", id).As<Node>(); if (runtime == null || !prototype.ContainsKey("growth")) return;
        var binding = prototype["growth"].AsGodotDictionary(); var controls = binding["controls"].AsGodotArray(); var motion = new Settings(); var source = points(controller, id, time); var transform = world(controller, id, time);
        var actor = prototype["actor"].AsGodotObject(); var growth = data(actor)!; double local = controller.Call("_local", actor, time).AsDouble();
        var sampledValues = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("sampled_values", actor, local).AsGodotDictionary(); var overrides = Get(sampledValues, "growth_overrides", new Settings()).AsGodotDictionary();
        var statePoints = state["points"].AsVector3Array(); int mode = config["mode"].AsInt32(); var bake = Get(config, "bake", new Settings()).AsGodotDictionary(); var frozenShapes = Get(Get(config, "frozen", new Settings()).AsGodotDictionary(), "growth_shapes", new Settings()).AsGodotDictionary();
        foreach (var row in controls)
        {
            var control = row.AsGodotDictionary(); var root = control["root"].AsGodotDictionary(); var inverse = (transform * _geometry.point_frame(growth, root, source)).AffineInverse(); var curve = new List<Vector3>();
            string controlId = control["id"].AsString(); var correction = Get(overrides, controlId, new Settings()).AsGodotDictionary(); double from = Get(correction, "from", 0.0).AsDouble(), to = Get(correction, "to", -1.0).AsDouble(), weight = 0;
            if (local >= from && (to < 0 || local <= to))
            {
                weight = Math.Clamp(Get(correction, "influence", 1.0).AsDouble(), 0, 1); double blend = Math.Max(0, Get(correction, "blend", .1).AsDouble());
                if (blend > 0) weight *= Mathf.SmoothStep(from, from + blend, local) * (to >= 0 ? 1 - Mathf.SmoothStep(to - blend, to, local) : 1);
            }
            var sampled = state;
            if (weight > 0 && mode == 4)
            {
                double at = Get(correction, "freeze_time", -1.0).AsDouble(); if (at < 0) { double start = Get(bake, "from", 0.0).AsDouble(); at = (time - start) * Get(correction, "time_scale", 1.0).AsDouble() + start + Get(correction, "time_offset", 0.0).AsDouble(); }
                if (!Mathf.IsEqualApprox(at, time))
                {
                    var baked = controller.Call("_baked", bake, Math.Clamp(at, Get(bake, "from", 0.0).AsDouble(), Get(bake, "to", time).AsDouble())).AsGodotDictionary(); if (baked.Count > 0) sampled = baked;
                }
            }
            Vector3 offset = Get(correction, "offset", Vector3.Zero).AsVector3(); var rotation = Basis.FromEuler(Get(correction, "rotation", Vector3.Zero).AsVector3() * Mathf.Pi / 180);
            Vector3[] frozen = mode == 3 ? Get(frozenShapes, controlId, Array.Empty<Vector3>()).AsVector3Array() : Array.Empty<Vector3>(), sampledPoints = sampled["points"].AsVector3Array();
            int count = control["count"].AsInt32(), first = control["first"].AsInt32();
            for (int i = 0; i < count; i++)
            {
                int index = first + i; if (index >= statePoints.Length) continue;
                Vector3 original = i < frozen.Length ? frozen[i] : inverse * statePoints[index], adjusted = index < sampledPoints.Length ? i < frozen.Length ? frozen[i] : inverse * sampledPoints[index] : original; float t = (float)i / Math.Max(1, count - 1);
                curve.Add(i > 0 ? original.Lerp(rotation * adjusted + offset * t * t, (float)weight) : Vector3.Zero);
            }
            var target = _geometry.curve(growth, root, Math.Max(1, curve.Count - 1)); var delta = new Vector3[curve.Count]; for (int i = 0; i < delta.Length; i++) delta[i] = curve[i] - target[i];
            motion[controlId] = new Settings { ["points"] = curve.ToArray(), ["delta_points"] = delta, ["influence"] = 1.0 };
        }
        foreach (var node in runtime.FindChildren("*", "MeshInstance3D", true, false))
        {
            var script = node.GetScript().As<Script>(); bool isGrowth = false; while (script != null) { if (script.ResourcePath == "res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd") { isGrowth = true; break; } script = script.GetBaseScript(); }
            if (!isGrowth) continue; var live = node.Get("data").As<Resource>(); live.Set("motion_guides", motion); live.Set("motion_weights", binding["weights"]); live.Set("motion_binding", binding["binding"]); live.Set("motion_influence", Math.Clamp(config["influence"].AsDouble(), 0, 1)); node.Call("update_growth");
        }
    }
}
