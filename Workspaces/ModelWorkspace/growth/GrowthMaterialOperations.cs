using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthMaterialOperations : RefCounted
{
    private static readonly Dictionary<string, long> Versions = new(StringComparer.Ordinal);
    private static readonly object VersionLock = new();
    private Shader? _shader;
    private readonly Dictionary<int, Shader> _variants = new();
    private static readonly string[] TextureFields = { "albedo_texture", "roughness_texture", "normal_texture", "alpha_texture" };
    private static readonly string[] Uniforms = { "root_color", "tip_color", "highlight_color", "roughness", "specular", "secondary_highlight", "highlight_shift", "backlight", "opacity", "emission", "variation", "bands", "edge_softness", "outline", "outline_color", "shaft_color", "feather_detail", "iridescence", "feather_pattern", "feather_pattern_color", "feather_pattern_scale", "feather_pattern_width", "left_vane_color", "right_vane_color", "shaft_roughness", "pattern", "pattern_color", "pattern_scale", "pattern_rotation", "pattern_mix", "pattern_seed", "texture_scale", "texture_offset", "texture_rotation" };
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Variant ObjectValue(GodotObject? value) => value != null ? Variant.From(value) : default;
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    private static bool ScriptType(GodotObject value, string path)
    { var script = value.GetScript().As<Script>(); while (script != null) { if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script = script.GetBaseScript(); } return false; }
    private static bool ObjectData(GodotObject value) => ScriptType(value, "res://scripts/actors/core/actor_object_data.gd");
    private static string Identity(string path) => ProjectSettings.GlobalizePath(path).Replace('\\', '/').SimplifyPath();
    public long source_version(string path) { lock (VersionLock) return Versions.GetValueOrDefault(Identity(path)); }
    public void invalidate_source(Variant source)
    {
        string path = source.VariantType == Variant.Type.Object && source.AsGodotObject() is Resource resource ? resource.ResourcePath : source.AsString();
        if (path.Length == 0) return; string identity = Identity(path); lock (VersionLock) Versions[identity] = Versions.GetValueOrDefault(identity) + 1;
    }
    public Resource copy_material(Resource source, bool unique)
    {
        var result = source.Duplicate(false); if (unique) { result.Set("asset_id", Guid.NewGuid().ToString("N")); result.Set("linked_source", ""); }
        var customAsset = source.Get("custom_asset").As<Resource>(); var custom = source.Get("custom").As<Material>();
        if (unique && customAsset != null) result.Set("custom_asset", customAsset.Call("copy_object")); if (unique && custom != null) result.Set("custom", custom.Duplicate(false));
        result.Set("texture_sources", source.Get("texture_sources").AsGodotDictionary().Duplicate(true)); result.Set("texture_stamps", source.Get("texture_stamps").AsGodotDictionary().Duplicate());
        if (source.Get("gradient").As<Gradient>() is Gradient gradient) result.Set("gradient", gradient.Duplicate(true));
        foreach (string field in TextureFields) if (source.Get(field).AsGodotObject() is NoiseTexture2D noise) result.Set(field, noise.Duplicate(true)); return result;
    }
    public GArray noise_signature(NoiseTexture2D texture)
    {
        var settings = new GArray();
        if (texture.Noise != null)
        {
            foreach (var property in texture.Noise.GetPropertyList())
            {
                if ((property["usage"].AsInt64() & (long)PropertyUsageFlags.Storage) == 0) continue; Variant value = texture.Noise.Get(property["name"].AsStringName());
                if (value.VariantType is Variant.Type.Float or Variant.Type.Int or Variant.Type.Bool or Variant.Type.Vector3) settings.Add(new GArray { property["name"], value });
            }
        }
        return new GArray { texture.Width, texture.Height, texture.AsNormalMap, texture.BumpStrength, texture.Seamless, settings };
    }
    public long signature(Resource source)
    {
        var values = new GArray();
        foreach (var property in source.GetPropertyList())
        {
            string name = property["name"].AsString(); if ((property["usage"].AsInt64() & (long)PropertyUsageFlags.Storage) == 0 || name is "script" or "resource_name" or "resource_path" or "resource_local_to_scene") continue;
            Variant value = source.Get(name); var obj = value.VariantType == Variant.Type.Object ? value.AsGodotObject() : null;
            if (obj is Gradient gradient) values.Add(new GArray { gradient.Colors, gradient.Offsets, (int)gradient.InterpolationMode, (int)gradient.InterpolationColorSpace });
            else if (obj is NoiseTexture2D noise) values.Add(noise_signature(noise)); else values.Add(value);
        }
        return Hash(values);
    }
    public Variant asset_values(Variant value, int depth)
    {
        if (depth > 12) return default;
        if (value.VariantType == Variant.Type.Object && value.AsGodotObject() is GodotObject obj)
        {
            if (ObjectData(obj)) return new GArray { obj.Get("type_id"), asset_values(obj.Get("values"), depth + 1) };
            if (ScriptType(obj, "res://scripts/actors/core/actor_object_reference.gd")) return asset_values(GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("resolve_reference", value), depth + 1);
            if (obj is Shader shader) return shader.Code;
        }
        if (value.VariantType == Variant.Type.String && value.AsString().GetExtension().ToLowerInvariant() == "gdshader") { string path = value.AsString(); return new GArray { value, Godot.FileAccess.GetModifiedTime(path), source_version(path) }; }
        if (value.VariantType == Variant.Type.Dictionary) { var result = new Settings(); foreach (var pair in value.AsGodotDictionary()) result[pair.Key] = asset_values(pair.Value, depth + 1); return result; }
        if (value.VariantType == Variant.Type.Array) { var result = new GArray(); foreach (var child in value.AsGodotArray()) result.Add(asset_values(child, depth + 1)); return result; }
        return value;
    }
    public Material? from_asset(Resource? resource)
    {
        if (resource is Material material) return material; if (resource == null || !ObjectData(resource)) return null;
        string type = resource.Get("type_id").AsString();
        if (type == "natural_material") return GD.Load<GDScript>("res://scripts/materials/natural_material_engine.gd").Call("create_spatial_material", resource.Call("get_value", "material_settings", new Settings())).As<Material>();
        var adapter = new BasicActorRuntime(); Material? result = null;
        try
        {
            if (type == "shader_material") result = adapter.Call("_create_shader_material", resource).As<Material>();
            else if (type == "material") { adapter.Set("material", new StandardMaterial3D()); adapter.Call("_apply_standard_material", resource); result = adapter.Get("material").As<Material>(); }
        }
        finally { adapter.Free(); }
        if (result is ShaderMaterial shaderMaterial && (shaderMaterial.Shader == null || shaderMaterial.Shader.GetMode() != Shader.Mode.Spatial)) return null; return result;
    }
    public Material prepare_custom(Resource source)
    {
        var custom = source.Get("custom").As<Material>(); if (custom is not ShaderMaterial material) { source.Set("runtime_key", Hash(custom)); return custom!; }
        if (material.Shader == null) return material;
        var uniforms = new GArray(); foreach (var row in material.Shader.GetShaderUniformList()) { var property = row.AsGodotDictionary(); uniforms.Add(new GArray { property["name"], material.GetShaderParameter(property["name"].AsStringName()) }); }
        long key = Hash(new GArray { material.Shader.Code, uniforms }); var copy = source.Get("custom_runtime").As<ShaderMaterial>(); if (copy != null && key == source.Get("custom_key").AsInt64()) return copy;
        var prepared = GD.Load<CSharpScript>("res://scripts/actors/core/ActorShaderTime.cs").Call("prepare", material.Shader.Code).AsGodotDictionary(); copy ??= new ShaderMaterial();
        string code = prepared["code"].AsString(); if (copy.Shader == null || copy.Shader.Code != code) copy.Shader = new Shader { Code = code };
        foreach (var row in uniforms) { var uniform = row.AsGodotArray(); copy.SetShaderParameter(uniform[0].AsStringName(), uniform[1]); }
        string time = prepared["uniform"].AsString(); if (time.Length == 0) time = material.GetMeta("kiwi_time_uniform", "").AsString();
        copy.SetMeta("kiwi_time_uniform", time); source.Set("custom_runtime", copy); source.Set("custom_key", key); source.Set("runtime_key", key); return copy;
    }
    public Resource preset(string name)
    {
        var result = new KiwiGrowthMaterial(); result.Set("title", name);
        void Set(string field, Variant value) => result.Set(field, value);
        switch (name)
        {
            case "Black hair": Set("root_color", new Color(.012f, .009f, .008f)); Set("tip_color", new Color(.055f, .03f, .02f)); Set("roughness", .4); Set("specular", .35); break;
            case "Warm hair": Set("root_color", new Color(.08f, .025f, .01f)); Set("tip_color", new Color(.32f, .12f, .035f)); Set("roughness", .45); break;
            case "Pale fur": Set("root_color", new Color(.28f, .25f, .22f)); Set("tip_color", new Color(.75f, .72f, .65f)); Set("roughness", .8); break;
            case "Striped coat": Set("root_color", new Color(.3f, .18f, .065f)); Set("tip_color", new Color(.65f, .42f, .15f)); Set("pattern", 1); Set("pattern_color", new Color(.025f, .02f, .01f)); Set("pattern_scale", 3.0); Set("roughness", .7); break;
            case "Flight feathers": Set("root_color", new Color(.42f, .23f, .08f)); Set("tip_color", new Color(.12f, .055f, .02f)); Set("feather_pattern", 1); Set("feather_pattern_width", .3); Set("specular", .2); break;
            case "Iridescent feathers": Set("root_color", new Color(.015f, .07f, .08f)); Set("tip_color", new Color(.12f, .2f, .25f)); Set("iridescence", .8); Set("roughness", .28); break;
            case "Stylized ink": Set("mode", 1); Set("root_color", new Color(.025f, .03f, .06f)); Set("tip_color", new Color(.13f, .18f, .3f)); Set("bands", 3); Set("outline", .04); Set("specular", .15); break;
        }
        return result;
    }
    public Resource style_preset(string name)
    {
        var result = new KiwiGrowthStyle();
        var presets = KiwiGrowthStyle.presets(); result.Set("title", name); result.Set("values", Get(presets, name, new Settings()).AsGodotDictionary().Duplicate(true)); return result;
    }
    public Material material(Resource source)
    {
        if (source.Get("mode").AsInt32() == 2)
        {
            if (source.Get("custom_asset").As<Resource>() is Resource asset)
            {
                long next = Hash(asset_values(asset, 0)); if (next != source.Get("custom_asset_key").AsInt64()) { source.Set("custom_asset_key", next); source.Set("custom", ObjectValue(from_asset(asset))); }
            }
            if (source.Get("custom").As<Material>() != null) return prepare_custom(source);
        }
        var stamps = source.Get("texture_stamps").AsGodotDictionary();
        foreach (var pair in source.Get("texture_sources").AsGodotDictionary())
        {
            string slot = pair.Key.AsString(), path = pair.Value.AsString(), extension = path.GetExtension().ToLowerInvariant();
            var stamp = new GArray { Godot.FileAccess.GetModifiedTime(path), source_version(path) }; Resource? cached = null;
            if ((extension == "tres" || extension == "res") && ResourceLoader.Exists(path)) { cached = ResourceLoader.Load(path); if (cached != null && ObjectData(cached)) stamp.Add(Hash(asset_values(cached, 0))); }
            var previous = Get(stamps, slot, new GArray()).AsGodotArray(); bool same = previous.Count == stamp.Count; for (int i = 0; same && i < stamp.Count; i++) same = previous[i].AsInt64() == stamp[i].AsInt64(); if (same) continue;
            Texture2D? texture = null;
            if (extension == "tres" || extension == "res")
            {
                var resource = cached; if (previous.Count == 0 || previous[0].AsInt64() != stamp[0].AsInt64() || previous[1].AsInt64() != stamp[1].AsInt64()) resource = ResourceLoader.Load(path, cacheMode: ResourceLoader.CacheMode.Replace);
                if (resource != null && ObjectData(resource)) { texture = GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("texture_for_object", resource).As<Texture2D>(); if (stamp.Count > 2) stamp[2] = Hash(asset_values(resource, 0)); }
                else texture = resource as Texture2D;
            }
            else
            {
                var image = Image.LoadFromFile(path); if (image != null && !image.IsEmpty()) { image.GenerateMipmaps(); texture = ImageTexture.CreateFromImage(image); }
            }
            stamps[slot] = stamp; source.Set(slot, ObjectValue(texture));
        }
        _shader ??= GD.Load<Shader>("res://Workspaces/ModelWorkspace/growth/growth_surface.gdshader"); int coverage = source.Get("coverage").AsInt32(); int variant = coverage == 0 && source.Get("opacity").AsDouble() < .999 ? 1 : coverage;
        if (variant > 0 && !_variants.ContainsKey(variant))
        {
            string code = _shader.Code;
            code = variant == 1 ? code.Replace("ALPHA_SCISSOR_THRESHOLD=.4;", "ALPHA_HASH_SCALE=1.;", StringComparison.Ordinal) : code.Replace("depth_prepass_alpha;", "depth_prepass_alpha, alpha_to_coverage;", StringComparison.Ordinal).Replace("ALPHA_SCISSOR_THRESHOLD=.4;", "ALPHA_SCISSOR_THRESHOLD=.4; ALPHA_ANTIALIASING_EDGE=.3;", StringComparison.Ordinal);
            _variants[variant] = new Shader { Code = code };
        }
        Shader selected = _variants.GetValueOrDefault(variant, _shader); var runtime = source.Get("runtime").As<ShaderMaterial>(); if (runtime == null) { runtime = new ShaderMaterial(); source.Set("runtime", runtime); }
        if (runtime.Shader != selected) { runtime.Shader = selected; source.Set("runtime_key", 0); }
        long key = signature(source); if (key == source.Get("runtime_key").AsInt64()) return runtime; source.Set("runtime_key", key);
        foreach (string name in Uniforms) runtime.SetShaderParameter(name, source.Get(name)); runtime.SetShaderParameter("stylized", source.Get("mode").AsInt32() == 1);
        foreach (string name in TextureFields) { runtime.SetShaderParameter("use_" + name, source.Get(name).AsGodotObject() != null); runtime.SetShaderParameter(name, source.Get(name)); }
        var gradient = source.Get("gradient").As<Gradient>(); GradientTexture1D? gradientTexture = gradient != null ? new GradientTexture1D { Gradient = gradient } : null;
        runtime.SetShaderParameter("use_gradient", gradient != null); runtime.SetShaderParameter("gradient_texture", ObjectValue(gradientTexture)); return runtime;
    }
}
