using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ModelNaturalSettings : RefCounted
{
    internal static readonly string[] Trees = { "Oak", "Maple", "Birch", "Willow", "Pine", "Spruce", "Fir", "Palm", "Tropical", "Mangrove", "Acacia", "Desert", "Twisted", "Dead", "Wind-shaped", "Ancient", "Fantasy" };
    internal static readonly string[] Plants = { "Bush", "Grass", "Flower", "Fern", "Vine", "Reed", "Succulent", "Mushroom", "Cactus" };
    internal static readonly string[] Rocks = { "Granite", "Basalt", "Limestone", "Sandstone", "Slate", "River stone", "Volcanic" };
    internal static readonly string[] Props = { "Log", "Stump", "Driftwood", "Root", "Stalactite", "Stalagmite" };
    private static readonly string[] Kinds = Trees.Select(n => "Tree / " + n).Concat(Plants.Select(n => "Plant / " + n)).Concat(Rocks.Select(n => "Rock / " + n)).Concat(Props.Select(n => "Prop / " + n)).ToArray();
    public Godot.Collections.Array kinds() => new(Kinds.Select(value => Variant.From(value)));
    internal static bool Accepts(string kind) => Array.IndexOf(Kinds, kind) >= 0;
    public bool accepts(string kind) => Accepts(kind);
    public Settings defaults(string kind)
    {
        bool tree = kind.StartsWith("Tree", StringComparison.Ordinal); string name = kind.Contains(" / ") ? kind.Split(" / ")[1] : "";
        var p = new Settings { ["seed"] = 1, ["height"] = tree ? 6.0 : 1.0, ["radius"] = tree ? .23 : .5, ["segments"] = 8, ["levels"] = 2, ["branches"] = 8, ["length"] = .46, ["angle"] = .9, ["curve"] = .2, ["droop"] = name == "Willow" ? .65 : .05, ["lean"] = name == "Wind-shaped" || name == "Twisted" ? .3 : 0.0, ["taper"] = .8, ["foliage"] = name == "Dead" ? 0.0 : 1.0, ["leaf_size"] = .28, ["roots"] = 5, ["irregularity"] = .3, ["detail"] = 12, ["season"] = 0, ["wind_strength"] = 0.0 };
        void Set(params (string, Variant)[] values) { foreach (var (key, value) in values) p[key] = value; }
        switch (name)
        {
            case "Maple": Set(("branches", 10), ("leaf_size", .23), ("angle", 1.2)); break;
            case "Birch": Set(("height", 8.0), ("radius", .13), ("length", .3), ("angle", .7)); break;
            case "Pine": Set(("branches", 12), ("height", 9.0), ("length", .4), ("levels", 1)); break;
            case "Spruce": Set(("branches", 16), ("height", 7.0), ("length", .55), ("droop", .22), ("levels", 1)); break;
            case "Fir": Set(("branches", 14), ("height", 10.0), ("length", .32), ("angle", 1.3), ("levels", 1)); break;
            case "Palm": Set(("height", 8.0), ("radius", .16), ("branches", 10), ("roots", 0), ("lean", .13)); break;
            case "Tropical": Set(("height", 10.0), ("radius", .4), ("branches", 12), ("leaf_size", .4), ("roots", 8)); break;
            case "Mangrove": Set(("height", 4.0), ("radius", .18), ("roots", 10), ("lean", .15)); break;
            case "Acacia": Set(("height", 5.0), ("length", .7), ("radius", .18), ("branches", 6), ("angle", 1.6)); break;
            case "Desert": Set(("height", 3.0), ("branches", 4), ("foliage", .2), ("curve", .45)); break;
            case "Twisted": Set(("height", 4.0), ("lean", .45), ("curve", .7), ("branches", 6)); break;
            case "Ancient": Set(("height", 8.0), ("radius", .7), ("roots", 12), ("branches", 5), ("curve", .5)); break;
            case "Fantasy": Set(("height", 12.0), ("radius", .6), ("lean", -.2), ("curve", .8), ("leaf_size", .65), ("branches", 9)); break;
            case "Wind-shaped": Set(("lean", .6), ("droop", .3), ("branches", 7), ("angle", .5)); break;
            case "Stalactite": Set(("height", 2.0), ("radius", .2)); break;
            case "Stalagmite": Set(("height", 1.4), ("radius", .4)); break;
            case "Cactus": Set(("branches", 3)); break;
        }
        return p;
    }
    public Godot.Collections.Array<Material> materials(string kind, Settings settings)
    {
        var engine = GD.Load<GDScript>("res://scripts/materials/natural_material_engine.gd"); Material bark = engine.Call("create_spatial_material", engine.Call("defaults", "wood/tree_bark")).As<Material>();
        if (kind.StartsWith("Rock", StringComparison.Ordinal)) { string name = kind.Split(" / ")[1].ToLowerInvariant().Replace(' ', '_'); if (!new[] { "granite", "limestone", "sandstone", "slate" }.Contains(name)) name = "granite"; var rock = engine.Call("defaults", "stone/" + name).AsGodotDictionary(); rock["mapping"] = "triplanar"; bark = engine.Call("create_spatial_material", rock).As<Material>(); }
        Color leafColor = new(.14f, .38f, .055f);
        if (kind.StartsWith("Plant", StringComparison.Ordinal) && kind != "Plant / Bush") { var stem = new StandardMaterial3D { AlbedoColor = new Color(.14f, .3f, .06f), Roughness = .8f }; bark = stem; if (kind == "Plant / Mushroom") { stem.AlbedoColor = new Color(.75f, .67f, .5f); leafColor = new Color(.55f, .18f, .035f); } }
        var flower = new StandardMaterial3D { AlbedoColor = new Color(.9f, .22f, .45f), CullMode = BaseMaterial3D.CullModeEnum.Disabled };
        var foliage = new ShaderMaterial { Shader = GD.Load<Shader>("res://Workspaces/ModelWorkspace/natural_leaf.gdshader") }; foliage.SetMeta("kiwi_natural_foliage", true);
        int season = Mathf.Clamp(settings.TryGetValue("season", out var s) ? s.AsInt32() : 0, 0, 3); foliage.SetShaderParameter("leaf_color", new[] { leafColor, new Color(.45f, .65f, .12f), new Color(.72f, .22f, .025f), new Color(.52f, .43f, .24f) }[season]); foliage.SetShaderParameter("wind_strength", Mathf.Clamp(settings.TryGetValue("wind_strength", out var wind) ? wind.AsDouble() : 0, 0, 1)); return new() { bark, foliage, flower };
    }
}
