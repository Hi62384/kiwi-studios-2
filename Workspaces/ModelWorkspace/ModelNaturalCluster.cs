using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelNaturalCluster : RefCounted
{
    private static readonly Dictionary<string, string> Presets = new() { ["Boulder field"] = "Rock / Granite", ["River stones"] = "Rock / River stone", ["Rockfall"] = "Rock / Slate", ["Forest grove"] = "Tree / Oak", ["Grass patch"] = "Plant / Grass", ["Deadwood"] = "Prop / Driftwood" };
    private readonly ModelNaturalSettings _settings = new();
    private readonly ModelNaturalGenerator _generator = new();
    public Godot.Collections.Array kinds() => new(Presets.Keys.Select(name => Variant.From("Cluster / " + name)));
    public bool accepts(Resource? item) => item != null && item.Get("parameters").AsGodotDictionary().ContainsKey("natural_cluster");
    private static Resource NewComponent() => new KiwiModelComponent();
    private static void Action(RefCounted session, string label, Action operation) { session.Call("begin"); try { operation(); session.Call("commit", label); } catch { session.Call("cancel"); throw; } }
    private static long MeshHash(Resource? mesh) => mesh == null ? 0 : unchecked((uint)GD.Hash(new Godot.Collections.Array { mesh.Get("vertices"), mesh.Get("faces") }));
    public Resource add(RefCounted session, string kind, Settings parameters, Vector3 position)
    {
        var root = NewComponent(); string id = Guid.NewGuid().ToString("N"); root.Set("id", id); root.Set("title", kind.Split(" / ").ElementAtOrDefault(1) ?? ""); root.Set("transform", new Transform3D(Basis.Identity, position)); var p = new Settings { ["natural_cluster"] = kind, ["seed"] = 1, ["count"] = 8, ["spread"] = 4.0, ["spacing"] = .5, ["scale_variation"] = .4 }; p.Merge(parameters, true); root.Set("parameters", p);
        Action(session, "Add natural cluster", () => { session.Get("document").As<Resource>().Get("components").AsGodotArray().Add(root); regenerate(session, root); var selected = session.Get("selected").AsGodotArray<string>(); selected.Clear(); selected.Add(id); }); return root;
    }
    public void regenerate(RefCounted session, Resource root)
    {
        var p = root.Get("parameters").AsGodotDictionary(); string name = p["natural_cluster"].AsString().Split(" / ").ElementAtOrDefault(1) ?? "", kind = Presets.GetValueOrDefault(name, "Rock / Granite"), rootId = root.Get("id").AsString(); var items = session.Get("document").As<Resource>().Get("components").AsGodotArray(); var old = new Dictionary<int, Resource>(); var taken = new List<Vector2>();
        foreach (var value in items) { var item = value.As<Resource>(); var settings = item.Get("parameters").AsGodotDictionary(); if (item.Get("parent_id").AsString() == rootId && settings.TryGetValue("_cluster_index", out var index)) old[index.AsInt32()] = item; }
        int count = Mathf.Clamp(p.TryGetValue("count", out var countValue) ? countValue.AsInt32() : 8, 1, 64), constrained = 0; var materials = _settings.materials(kind, new()); var source = _settings.defaults(kind); var live = new HashSet<int>(); if (kind.StartsWith("Tree", StringComparison.Ordinal)) source["levels"] = 1;
        double Number(string field, double fallback) => p.TryGetValue(field, out var value) ? value.AsDouble() : fallback;
        for (int index = 0; index < count; index++)
        {
            using var rng = new RandomNumberGenerator { Seed = unchecked((uint)GD.Hash(new Godot.Collections.Array { (long)Number("seed", 1), index })) }; Vector2 point = Vector2.Zero; bool clear = false;
            for (int attempt = 0; attempt < 100; attempt++) { point = Vector2.FromAngle((float)(rng.Randf() * Math.Tau)) * (float)Math.Sqrt(rng.Randf()) * (float)Math.Max(.01, Number("spread", 4)); clear = taken.All(other => point.DistanceTo(other) >= Number("spacing", .5)); if (clear) break; }
            if (!clear) { constrained++; continue; } live.Add(index); bool fresh = !old.TryGetValue(index, out var item);
            if (fresh) { item = NewComponent(); item.Set("id", rootId + ":natural:" + index); item.Set("parent_id", rootId); item.Set("title", kind.Split(" / ")[1] + " " + (index + 1)); items.Add(item); }
            var previous = item!.Get("parameters").AsGodotDictionary().Duplicate(true); Transform3D currentPose = item.Get("transform").AsTransform3D(), oldPose = previous.TryGetValue("_cluster_pose", out var oldPoseValue) ? oldPoseValue.AsTransform3D() : currentPose;
            bool manualPose = !fresh && !currentPose.IsEqualApprox(oldPose), manualMesh = (previous.TryGetValue("_cluster_manual_mesh", out var manual) && manual.AsBool()) || (!fresh && (item.Get("generator").AsString().Length == 0 || (item.Get("mesh").As<Resource>() != null && MeshHash(item.Get("mesh").As<Resource>()) != (previous.TryGetValue("_cluster_mesh", out var oldHash) ? oldHash.AsInt64() : 0))));
            double variation = Math.Clamp(Number("scale_variation", .4), 0, .9); float size = rng.RandfRange((float)(1 - variation), (float)(1 + variation)); var pose = new Transform3D(new Basis(Vector3.Up, (float)(rng.Randf() * Math.Tau)).Scaled(Vector3.One * size), new Vector3(point.X, 0, point.Y)); if (!manualPose) item.Set("transform", pose);
            Vector3 placed = item.Get("transform").AsTransform3D().Origin; taken.Add(new Vector2(placed.X, placed.Z));
            if (!manualMesh) { var settings = source.Duplicate(true); settings["seed"] = rng.RandiRange(0, int.MaxValue); var generated = _generator.Generate(kind, settings, () => false); if (generated["mesh"].As<Resource>() != null) { item.Set("generator", kind); item.Set("mesh", generated["mesh"]); item.Set("parameters", settings); if (fresh) item.Set("surface_materials", materials); } }
            var output = item.Get("parameters").AsGodotDictionary(); output["_cluster_index"] = index; output["_cluster_pose"] = pose; output["_cluster_mesh"] = MeshHash(item.Get("mesh").As<Resource>()); output["_cluster_manual_mesh"] = manualMesh;
        }
        foreach (var entry in old)
        {
            if (live.Contains(entry.Key)) continue; var item = entry.Value;
            if (items.Any(value => value.As<Resource>().Get("parent_id").AsString() == item.Get("id").AsString())) { item.Get("parameters").AsGodotDictionary().Remove("_cluster_index"); continue; } items.Remove(item);
        }
        p["_cluster_warning"] = constrained > 0 ? $"Placed {count - constrained} / {count}: increase spread or reduce spacing." : "";
    }
    public void properties(Control workspace, Resource item, Node parent)
    {
        parent.AddChild(new Label { Text = "NATURAL CLUSTER · " + item.Get("title").AsString() }); var p = item.Get("parameters").AsGodotDictionary(); if (p.TryGetValue("_cluster_warning", out var warning) && warning.AsString().Length > 0) parent.AddChild(new Label { Text = warning.AsString(), AutowrapMode = TextServer.AutowrapMode.WordSmart });
        foreach (var (title, field, minimum, maximum, step) in new[] { ("Seed", "seed", 0.0, 2147483647.0, 1.0), ("Count", "count", 1.0, 64.0, 1.0), ("Spread (m)", "spread", .01, 100.0, .1), ("Spacing (m)", "spacing", 0.0, 20.0, .1), ("Scale variation", "scale_variation", 0.0, .9, .01) })
        {
            var row = new HBoxContainer(); parent.AddChild(row); row.AddChild(new Label { Text = title, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }); var number = new DragNumber(); number.Set("min_value", minimum); number.Set("max_value", maximum); number.Set("step", step); number.Call("set_value_no_signal", p.TryGetValue(field, out var value) ? value.AsDouble() : 0); row.AddChild(number);
            void Write(double changed) { var session = workspace.Get("session").As<RefCounted>(); Action(session, "Change natural cluster", () => { var current = session.Get("document").As<Resource>().Call("component", item.Get("id")).As<Resource>(); current.Get("parameters").AsGodotDictionary()[field] = changed; regenerate(session, current); }); }
            number.Connect("value_changed", Callable.From<double>(Write)); number.Connect("drag_committed", Callable.From<double>(Write));
        }
    }
}
