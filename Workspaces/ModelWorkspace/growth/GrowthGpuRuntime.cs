using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthGpuRuntime : RefCounted
{
    private readonly SurfaceGrowthGeometry _geometry = new();
    private readonly SurfaceGrowthSettings _settings = new();
    private static Settings Dict(GodotObject owner, string key) => owner.Get(key).AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    public bool supports(Resource data)
    {
        var appearance = data.Get("appearance").As<Resource>(); if (appearance == null || appearance.Get("mode").AsInt32() == 2) return false;
        foreach (var row in data.Get("regions").AsGodotArray())
        {
            var region = row.AsGodotDictionary(); var material = Get(region, "material").As<Resource>();
            if (Get(region, "enabled", true).AsBool() && material != null && material.Get("mode").AsInt32() == 2) return false;
        }
        return true;
    }
    public Texture2D upload(GodotObject owner, string name, float[] values)
    {
        int pixels = Math.Max(1, (values.Length + 3) / 4), width = Math.Min(256, pixels), height = (pixels + width - 1) / width;
        var bytes = new byte[width * height * 16]; Buffer.BlockCopy(values, 0, bytes, 0, values.Length * sizeof(float));
        using var image = Image.CreateFromData(width, height, false, Image.Format.Rgbaf, bytes); var textures = Dict(owner, "textures"); var texture = Get(textures, name).As<ImageTexture>();
        if (texture == null || texture.GetWidth() != width || texture.GetHeight() != height) { texture = ImageTexture.CreateFromImage(image); textures[name] = texture; } else texture.Update(image);
        owner.Set("uploads", owner.Get("uploads").AsInt64() + 1); owner.Set("uploaded_bytes", owner.Get("uploaded_bytes").AsInt64() + bytes.Length); owner.Get("material").As<ShaderMaterial>().SetShaderParameter(name, texture); return texture;
    }
    public float[] point_table(Vector3[] points)
    {
        var result = new float[points.Length * 4]; for (int i = 0; i < points.Length; i++) { result[i * 4] = points[i].X; result[i * 4 + 1] = points[i].Y; result[i * 4 + 2] = points[i].Z; } return result;
    }
    private static void CopyUniforms(ShaderMaterial from, ShaderMaterial to)
    {
        foreach (var row in from.Shader!.GetShaderUniformList()) { StringName name = row.AsGodotDictionary()["name"].AsStringName(); to.SetShaderParameter(name, from.GetShaderParameter(name)); }
    }
    public void update(GodotObject owner, MeshInstance3D instance, Vector3[] posed, bool skinned)
    {
        var data = instance.Get("data").As<Resource>(); var appearance = data.Get("appearance").As<Resource>(); var basis = appearance.Call("material").As<ShaderMaterial>();
        var material = owner.Get("material").As<ShaderMaterial>(); if (material == null) { material = new ShaderMaterial { Shader = basis.Shader }; owner.Set("material", material); }
        if (material.Shader != basis.Shader) { material.Shader = basis.Shader; owner.Set("base_key", -1); }
        if (owner.Get("base_key").AsInt64() != appearance.Get("runtime_key").AsInt64())
        {
            CopyUniforms(basis, material); owner.Set("base_key", appearance.Get("runtime_key")); foreach (var pair in Dict(owner, "textures")) material.SetShaderParameter(pair.Key.AsStringName(), pair.Value);
        }
        var roots = data.Get("roots").AsGodotArray(); var style = data.Get("growth_style").As<Resource>();
        long nextRoots = Hash(new GArray { data.Get("generation_key"), data.Get("source_points"), data.Get("revision"), style != null ? style.Get("values") : new Settings() });
        if (owner.Get("roots_key").AsInt64() != nextRoots)
        {
            owner.Set("roots_key", nextRoots); var triangles = new float[roots.Count * 4]; double extent = .01; _settings.prepare_regions(data);
            for (int i = 0; i < roots.Count; i++)
            {
                var root = roots[i].AsGodotDictionary(); var edit = _geometry.PreparedStyle(data, root); var settings = _geometry.PreparedSettings(data, root); Vector3I ids = root["triangle"].AsVector3I();
                triangles[i * 4] = ids.X; triangles[i * 4 + 1] = ids.Y; triangles[i * 4 + 2] = ids.Z; triangles[i * 4 + 3] = Math.Max(.001f, edit["length"].AsSingle()); extent = Math.Max(extent, Math.Max(edit["length"].AsDouble() * 2, Get(settings, "width", .14).AsDouble() * 2));
            }
            owner.Set("growth_extent", extent); upload(owner, "growth_triangles", triangles); upload(owner, "growth_rest_points", point_table(data.Get("source_points").AsVector3Array())); owner.Set("source_key", 0);
        }
        long nextSource = Hash(posed);
        if (owner.Get("source_key").AsInt64() != nextSource)
        {
            owner.Set("source_key", nextSource); upload(owner, "growth_posed_points", point_table(posed)); Aabb bounds = posed.Length > 0 ? new Aabb(posed[0], Vector3.Zero) : new Aabb(); foreach (Vector3 point in posed) bounds = bounds.Expand(point); owner.Set("bounds", bounds);
        }
        var guides = Dict(data, "motion_guides"); var guideIds = owner.Get("guide_ids").AsGodotArray();
        if (owner.Get("binding_key").AsInt64() != data.Get("motion_binding").AsInt64() || (guideIds.Count == 0 && guides.Count > 0))
        {
            owner.Set("binding_key", data.Get("motion_binding")); string[] ids = guides.Keys.Select(value => value.AsString()).OrderBy(value => value, StringComparer.Ordinal).ToArray(); guideIds = new GArray(ids.Select(value => Variant.From(value))); owner.Set("guide_ids", guideIds);
            var lookup = new Dictionary<string, int>(StringComparer.Ordinal); for (int i = 0; i < ids.Length; i++) lookup[ids[i]] = i;
            var indices = new float[roots.Count * 4]; Array.Fill(indices, -1); var weights = new float[indices.Length]; var linksByRoot = Dict(data, "motion_weights");
            for (int i = 0; i < roots.Count; i++)
            {
                string id = roots[i].AsGodotDictionary()["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture); var links = Get(linksByRoot, id, new Settings()).AsGodotDictionary(); int at = 0; float total = 0;
                foreach (var pair in links)
                {
                    if (at >= 4) break; if (!lookup.TryGetValue(pair.Key.AsString(), out int guide)) continue;
                    indices[i * 4 + at] = guide; weights[i * 4 + at] = Math.Max(0, pair.Value.AsSingle()); total += weights[i * 4 + at]; at++;
                }
                for (int k = 0; k < 4; k++) weights[i * 4 + k] /= Math.Max(.00001f, total);
            }
            upload(owner, "growth_guide_indices", indices); upload(owner, "growth_guide_weights", weights); owner.Set("motion_key", 0);
        }
        long nextMotion = Hash(guides);
        if (guideIds.Count > 0 && nextMotion != owner.Get("motion_key").AsInt64())
        {
            owner.Set("motion_key", nextMotion); var points = new List<Vector3>();
            foreach (var id in guideIds)
            {
                var deltas = Get(Get(guides, id, new Settings()).AsGodotDictionary(), "delta_points", new[] { Vector3.Zero, Vector3.Zero }).AsVector3Array(); points.AddRange(deltas.Length == 9 ? deltas : _geometry.resample_curve(deltas, 9));
            }
            upload(owner, "growth_guide_points", point_table(points.ToArray()));
        }
        material.SetShaderParameter("growth_skin_attachment", skinned); material.SetShaderParameter("growth_guide_motion", guideIds.Count > 0 && guides.Count > 0); material.SetShaderParameter("growth_motion_influence", data.Get("motion_influence"));
        double density = data.Get("lod_density").AsDouble(); material.SetShaderParameter("lod_density", density); material.SetShaderParameter("coverage_scale", Math.Min(4, 1 / Math.Sqrt(density)));
        float margin = owner.Get("growth_extent").AsSingle(); foreach (var pair in guides) foreach (Vector3 point in Get(pair.Value.AsGodotDictionary(), "delta_points", Array.Empty<Vector3>()).AsVector3Array()) margin = Math.Max(margin, point.Length() * 2);
        instance.CustomAabb = owner.Get("bounds").AsAabb().Grow(margin); instance.MaterialOverride = material;
    }
    public void bind_regions(GodotObject owner, MeshInstance3D instance, bool deformed)
    {
        var data = instance.Get("data").As<Resource>(); var regions = data.Get("regions").AsGodotArray(); var material = owner.Get("material").As<ShaderMaterial>();
        if (regions.Count == 0) { instance.MaterialOverride = material; return; }
        instance.MaterialOverride = null; var used = new HashSet<ulong>(); var ready = new HashSet<ulong>(); var regional = Dict(owner, "regional");
        for (int surface = 0; surface < instance.Mesh.GetSurfaceCount(); surface++)
        {
            int index = Get(Dict(data, "surface_regions"), surface, -1).AsInt32(); var appearance = data.Get("appearance").As<Resource>();
            if (index >= 0 && index < regions.Count && Get(regions[index].AsGodotDictionary(), "material").As<Resource>() is Resource local) appearance = local;
            if (appearance.Get("mode").AsInt32() == 2) { instance.SetSurfaceOverrideMaterial(surface, appearance.Call("material").As<Material>()); continue; }
            ulong id = appearance.GetInstanceId(); used.Add(id); if (!regional.ContainsKey(id)) regional[id] = new Settings { ["material"] = new ShaderMaterial(), ["key"] = -1 };
            var entry = regional[id].AsGodotDictionary(); var target = entry["material"].As<ShaderMaterial>();
            if (ready.Add(id))
            {
                var source = appearance.Call("material").As<ShaderMaterial>(); if (target.Shader != source.Shader) { target.Shader = source.Shader; entry["key"] = -1; }
                if (entry["key"].AsInt64() != appearance.Get("runtime_key").AsInt64()) { CopyUniforms(source, target); entry["key"] = appearance.Get("runtime_key"); }
                if (deformed)
                {
                    foreach (var pair in Dict(owner, "textures")) target.SetShaderParameter(pair.Key.AsStringName(), pair.Value);
                    foreach (string name in new[] { "growth_skin_attachment", "growth_guide_motion", "growth_motion_influence", "lod_density", "coverage_scale" }) target.SetShaderParameter(name, material.GetShaderParameter(name));
                }
                else
                {
                    target.SetShaderParameter("growth_skin_attachment", false); target.SetShaderParameter("growth_guide_motion", false); double density = data.Get("lod_density").AsDouble(); target.SetShaderParameter("lod_density", density); target.SetShaderParameter("coverage_scale", Math.Min(4, 1 / Math.Sqrt(density)));
                }
            }
            instance.SetSurfaceOverrideMaterial(surface, target);
        }
        foreach (var id in regional.Keys.ToArray()) if (!used.Contains(id.AsUInt64())) regional.Remove(id);
    }
}
