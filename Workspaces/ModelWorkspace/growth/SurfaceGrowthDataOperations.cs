using Godot;
using Settings = Godot.Collections.Dictionary;

public partial class SurfaceGrowthGeometry
{
    public Resource copy_data(Resource source)
    {
        var result = NewResource("growth/surface_growth_data");
        foreach (string key in new[] { "source_id", "faces", "topology", "source_points", "source_skin", "source_to_rig", "source_valid", "rigid_bone", "rigid_offset", "groom_enabled", "protected_faces", "generation_key", "error", "revision" }) result.Set(key, source.Get(key));
        foreach (string key in new[] { "settings", "individual", "rendering", "groom", "guides" }) result.Set(key, Dict(source, key).Duplicate(true));
        foreach (string key in new[] { "roots", "source_weights", "brush_presets", "surface_triangles", "groom_layers" }) result.Set(key, source.Get(key).AsGodotArray().Duplicate(true));
        var appearance = source.Get("appearance").As<Resource>(); var style = source.Get("growth_style").As<Resource>();
        result.Set("appearance", appearance != null ? appearance.Call("copy_material", false) : default(Variant)); result.Set("growth_style", style != null ? style.Duplicate(true) : default(Variant));
        var regions = result.Get("regions").AsGodotArray();
        foreach (var value in source.Get("regions").AsGodotArray())
        {
            var row = value.AsGodotDictionary().Duplicate(true);
            if (Get(row, "material").As<Resource>() is Resource material && material.HasMethod("copy_material")) row["material"] = material.Call("copy_material", false);
            if (Get(row, "style").As<Resource>() is Resource local) row["style"] = local.Duplicate(true); regions.Add(row);
        }
        return result;
    }
}
