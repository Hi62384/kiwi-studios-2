using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class EnvironmentSessionOperations : RefCounted
{
    private readonly ModelDocumentOperations _documents = new();
    private readonly ModelSessionHistory _history = new();
    private readonly ModelComponentOperations _components = new();
    private readonly ModelReferenceRemap _remap = new();
    private readonly ModelMeshOperations _meshes = new();
    private static Resource Doc(RefCounted session) => session.Get("document").As<Resource>();
    private static Settings Dict(GodotObject value, string key) => value.Get(key).AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Resource? Terrain(RefCounted session, string id) => Doc(session).Call("terrain", id).As<Resource>();
    private static void Action(RefCounted session, string title, Action operation)
    { session.Call("begin"); try { operation(); session.Call("commit", title); } catch { session.Call("cancel"); throw; } }
    private static void Changed(RefCounted session) => session.EmitSignal("changed");
    public bool begin_terrain(RefCounted session, string id, bool material)
    {
        var item = _documents.component(Doc(session), id); if (item == null || !_documents.editable_component(Doc(session), item) || Terrain(session, id) == null) return false;
        session.Set("_terrain_stroke", new Settings { ["id"] = id, ["before"] = new Settings(), ["after"] = new Settings(), ["material"] = material }); return true;
    }
    public void sculpt(RefCounted session, Vector2 center, double radius, double amount, double falloff, int operation, double flatten, Settings options)
    {
        var stroke = Dict(session, "_terrain_stroke"); if (stroke.Count == 0) return; string id = stroke["id"].AsString(); var terrain = Terrain(session, id); if (terrain == null) return;
        var edits = stroke["material"].AsBool() ? terrain.Call("paint_material", center, radius, amount, falloff, operation == 1).AsGodotDictionary() : terrain.Call("sculpt", center, radius, amount, falloff, operation, flatten, options).AsGodotDictionary();
        var before = stroke["before"].AsGodotDictionary(); var after = stroke["after"].AsGodotDictionary(); var next = edits["after"].AsGodotDictionary();
        foreach (var pair in edits["before"].AsGodotDictionary()) { if (!before.ContainsKey(pair.Key)) before[pair.Key] = pair.Value; after[pair.Key] = next[pair.Key]; }
        patch_editable(session, id, next); Changed(session);
    }
    public void patch_editable(RefCounted session, string id, Settings samples)
    {
        var item = _documents.component(Doc(session), id); var mesh = item?.Get("mesh").As<Resource>(); var terrain = Terrain(session, id); if (mesh == null || terrain == null) return;
        var vertices = mesh.Get("vertices").AsVector3Array(); int resolution = terrain.Get("resolution").AsInt32();
        if (vertices.Length != resolution * resolution)
        {
            int side = (int)Math.Round(Math.Sqrt(vertices.Length), MidpointRounding.AwayFromZero); if (side < 2 || side * side != vertices.Length) return;
            for (int i = 0; i < vertices.Length; i++)
            {
                int x = (int)Math.Round((double)(i % side) / (side - 1) * (resolution - 1), MidpointRounding.AwayFromZero), z = (int)Math.Round((double)(i / side) / (side - 1) * (resolution - 1), MidpointRounding.AwayFromZero);
                if (samples.ContainsKey(x + z * resolution)) vertices[i].Y = terrain.Call("height", x, z).AsSingle();
            }
        }
        else foreach (var pair in samples) { int index = pair.Key.AsInt32(); if (index >= 0 && index < vertices.Length) vertices[index].Y = terrain.Call("height", index % resolution, index / resolution).AsSingle(); }
        mesh.Set("vertices", vertices);
    }
    public void apply_terrain(RefCounted session, string id, Settings samples, bool material)
    {
        var terrain = Terrain(session, id); if (terrain == null) return;
        if (material) terrain.Call("apply_material_samples", samples); else { terrain.Call("apply_samples", samples); patch_editable(session, id, samples); }
    }
    public void finish_terrain(RefCounted session, bool cancelled)
    {
        var stroke = Dict(session, "_terrain_stroke"); if (stroke.Count == 0) return; session.Set("_terrain_stroke", new Settings()); string id = stroke["id"].AsString(); bool material = stroke["material"].AsBool(); var before = stroke["before"].AsGodotDictionary(); var after = stroke["after"].AsGodotDictionary();
        if (cancelled) { apply_terrain(session, id, before, material); Changed(session); return; } if (after.Count == 0) return;
        before = before.Duplicate(); after = after.Duplicate(); var reference = GodotObject.WeakRef(session) ?? throw new InvalidOperationException("Cannot retain terrain history owner.");
        void Apply(Settings samples) { var owner = reference.GetRef().As<RefCounted>(); if (owner != null) apply_terrain(owner, id, samples, material); }
        session.Call("custom_action", material ? "Paint terrain material" : "Sculpt terrain", Callable.From(() => Apply(before)), Callable.From(() => Apply(after)), after.Count);
    }
    public void regenerate_terrain(RefCounted session, string id, Settings settings, bool resetEdits)
    {
        var terrain = Terrain(session, id); if (terrain == null) return;
        Action(session, "Regenerate terrain", () =>
        {
            string[] keys = { "dimensions", "resolution", "seed", "geology", "base_height", "amplitude", "frequency", "generation", "erosion", "caves", "hydrology", "biomes", "voxel_height", "voxel_cell_budget" };
            foreach (var pair in settings) if (Array.IndexOf(keys, pair.Key.AsString()) >= 0) terrain.Set(pair.Key.AsStringName(), pair.Value); if (resetEdits) terrain.Set("edits", Array.Empty<float>());
            foreach (string method in new[] { "prepare", "prepare_water", "prepare_biomes", "prepare_volumes", "prepare_cave_biomes" }) terrain.Call(method);
            terrain.Set("revision", terrain.Get("revision").AsInt64() + 1); _documents.component(Doc(session), id)!.Set("mesh", terrain.Call("editable_mesh"));
        });
    }
}
