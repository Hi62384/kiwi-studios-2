using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

// Saved growth resources retain their legacy schema while all settings behavior
// runs here. Dictionaries remain shared with the resource, as in the editor.
public partial class SurfaceGrowthSettings : RefCounted
{
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Settings Dict(GodotObject value, string key) => value.Get(key).AsGodotDictionary();
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    public Settings base_settings(GodotObject data)
    {
        var style = data.Get("growth_style").AsGodotObject();
        var settings = Dict(data, "settings");
        long signature = Hash(new GArray { settings, style != null ? style.Get("values") : new Settings() });
        var cache = Dict(data, "base_cache");
        if (cache.Count == 0 || signature != data.Get("base_signature").AsInt64())
        {
            cache = settings.Duplicate();
            if (style != null) cache.Merge(Dict(style, "values"), true);
            data.Set("base_signature", signature); data.Set("base_cache", cache);
        }
        return cache;
    }
    public void prepare_regions(GodotObject data)
    {
        // Refresh the style signature before testing the region cache: editing a
        // shared style must invalidate regions even without a geometry revision.
        var basis = base_settings(data);
        long revision = data.Get("revision").AsInt64(), signature = data.Get("base_signature").AsInt64();
        if (data.Get("region_revision").AsInt64() == revision && data.Get("region_base").AsInt64() == signature) return;
        data.Set("region_revision", revision); data.Set("region_base", signature);
        var roots = Dict(data, "root_regions"); roots.Clear();
        var regionSettings = Dict(data, "region_settings"); regionSettings.Clear();
        var regions = data.Get("regions").AsGodotArray();
        var rootRows = data.Get("roots").AsGodotArray();
        var signatures = new GArray();
        for (int index = 0; index < System.Math.Min(16, regions.Count); index++)
        {
            var region = regions[index].AsGodotDictionary();
            if (!Get(region, "enabled", true).AsBool()) continue;
            var style = Get(region, "style").AsGodotObject();
            var settings = basis.Duplicate();
            if (style != null) settings.Merge(Dict(style, "values"), true);
            regionSettings[index] = settings;
            int[] ids = Get(region, "roots", System.Array.Empty<int>()).AsInt32Array();
            int[] faces = Get(region, "faces", System.Array.Empty<int>()).AsInt32Array();
            bool all = Get(region, "all", false).AsBool();
            foreach (int id in ids) roots[id] = index;
            if (faces.Length > 0 || all)
            {
                var faceSet = new System.Collections.Generic.HashSet<int>(faces);
                foreach (var row in rootRows)
                {
                    var root = row.AsGodotDictionary();
                    if (all || faceSet.Contains(root["face"].AsInt32())) roots[root["id"]] = index;
                }
            }
            signatures.Add(new GArray { index, ids, faces, all, style != null ? style.Get("values") : new Settings() });
        }
        data.Set("region_signature", Hash(signatures));
    }
    public Settings root_settings(GodotObject data, Settings root)
    {
        prepare_regions(data);
        var index = Get(Dict(data, "root_regions"), root["id"], -1);
        return Get(Dict(data, "region_settings"), index, data.Get("base_cache")).AsGodotDictionary();
    }
    public Material? region_material(GodotObject data, int index)
    {
        var regions = data.Get("regions").AsGodotArray();
        if (index >= 0 && index < regions.Count)
        {
            var material = Get(regions[index].AsGodotDictionary(), "material").AsGodotObject();
            if (material != null && material.HasMethod("material")) return material.Call("material").As<Material>();
        }
        return data.Get("material").As<Material>();
    }
    public Settings defaults(int kind) => new()
    {
        ["type"] = kind, ["density"] = kind == 1 ? 120.0 : kind == 2 ? 12.0 : 35.0,
        ["length"] = kind == 1 ? .12 : kind == 2 ? .45 : .65, ["thickness"] = kind == 1 ? .008 : .012,
        ["seed"] = 31, ["quality"] = 1, ["shape"] = 0, ["curvature"] = .15, ["taper"] = .9,
        ["variation"] = .25, ["direction"] = Vector3.Down, ["direction_mode"] = 0, ["direction_blend"] = .4,
        ["orientation_variation"] = .15, ["width"] = .14, ["feather_type"] = 1, ["overlap"] = .3,
        ["arrangement"] = 0, ["rows"] = 4, ["spacing"] = 0.0, ["guard_hairs"] = .12,
        ["color"] = new Color(.28f, .12f, .055f), ["candidate_multiplier"] = 2.0
    };
}
