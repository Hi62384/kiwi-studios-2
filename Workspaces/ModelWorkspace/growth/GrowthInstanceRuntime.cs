using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthInstanceRuntime : RefCounted
{
    private readonly SurfaceGrowthGeometry _geometry = new();
    private readonly SurfaceGrowthSettings _settings = new();
    private readonly GrowthGpuRuntime _gpu = new();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Resource? Data(MeshInstance3D instance) => instance.Get("data").As<Resource>();
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    private static bool HasRegions(Resource data) => data.Get("regions").AsGodotArray().Count > 0;
    public Material base_override(MeshInstance3D instance)
    {
        var appearance = Data(instance)!.Get("appearance").As<Resource>(); var source = appearance.Call("material").As<Material>(); if (source is not ShaderMaterial material) return source;
        var copy = instance.Get("appearance_instance").As<ShaderMaterial>(); if (copy == null) { copy = new ShaderMaterial(); instance.Set("appearance_instance", copy); }
        if (copy.Shader != material.Shader) { copy.Shader = material.Shader; instance.Set("appearance_key", -1); }
        if (instance.Get("appearance_source").As<Resource>() != appearance || instance.Get("appearance_key").AsInt64() != appearance.Get("runtime_key").AsInt64())
        {
            foreach (var row in material.Shader!.GetShaderUniformList()) { var property = row.AsGodotDictionary(); StringName name = property["name"].AsStringName(); copy.SetShaderParameter(name, material.GetShaderParameter(name)); }
            copy.SetMeta("kiwi_time_uniform", material.GetMeta("kiwi_time_uniform", "")); instance.Set("appearance_source", appearance); instance.Set("appearance_key", appearance.Get("runtime_key"));
        }
        return copy;
    }
    public void set_growth_time(MeshInstance3D instance, double time)
    {
        void Set(Material? material)
        {
            if (material is not ShaderMaterial shader) return; string uniform = shader.GetMeta("kiwi_time_uniform", "").AsString(); if (uniform.Length > 0) shader.SetShaderParameter(uniform, time);
        }
        if (instance.MaterialOverride != null) Set(instance.MaterialOverride);
        else if (instance.Mesh != null) for (int surface = 0; surface < instance.Mesh.GetSurfaceCount(); surface++) Set(instance.GetSurfaceOverrideMaterial(surface) ?? instance.Mesh.SurfaceGetMaterial(surface));
    }
    public void configure(MeshInstance3D instance, Resource component, bool independent)
    {
        var growth = component.Get("growth").As<Resource>(); var data = independent ? growth.Call("copy_data").As<Resource>() : growth;
        instance.Set("data", data); instance.Mesh = _geometry.render(data, Array.Empty<Vector3>()); instance.Layers = 1;
    }
    public void update_lod(MeshInstance3D instance)
    {
        var data = Data(instance)!; var appearance = data.Get("appearance").As<Resource>(); var rendering = data.Get("rendering").AsGodotDictionary();
        bool final = instance.IsInsideTree() && instance.GetViewport().GetMeta("kiwi_final_growth", false).AsBool(); data.Set("render_final", final); double density = 1; int detail = 0;
        if (instance.IsInsideTree() && Get(rendering, "automatic_lod", true).AsBool() && appearance != null && appearance.Get("mode").AsInt32() != 2 && !final)
        {
            var camera = instance.GetViewport().GetCamera3D(); if (camera != null)
            {
                double near = Math.Max(.1, Get(rendering, "near", 4.0).AsDouble()), far = Math.Max(near + .1, Get(rendering, "far", 16.0).AsDouble());
                double progress = Mathf.SmoothStep(near, far, camera.GlobalPosition.DistanceTo(instance.GlobalPosition)); density = Mathf.Lerp(1, Math.Clamp(Get(rendering, "minimum_density", .15).AsDouble(), .05, 1), progress); detail = progress < .3 ? 0 : progress < .8 ? 1 : 2;
            }
        }
        if (appearance != null && appearance.Get("mode").AsInt32() == 1) density *= .55;
        data.Set("lod_density", density); data.Set("lod_upper", Math.Min(1, Math.Ceiling((density + .05) * 4) / 4)); data.Set("lod_detail", detail);
        void Uniforms(ShaderMaterial material) { material.SetShaderParameter("lod_density", density); material.SetShaderParameter("coverage_scale", Math.Min(4, 1 / Math.Sqrt(density))); }
        if (instance.MaterialOverride is ShaderMaterial shader && appearance != null && appearance.Get("mode").AsInt32() != 2) Uniforms(shader);
        if (HasRegions(data) && appearance != null)
            for (int region = -1; region < data.Get("regions").AsGodotArray().Count; region++)
                if (appearance.Get("mode").AsInt32() != 2 && _settings.region_material(data, region) is ShaderMaterial material && material.Shader == appearance.Get("runtime").As<ShaderMaterial>()?.Shader) Uniforms(material);
    }
    public void update_growth(MeshInstance3D instance)
    {
        var data = Data(instance); if (data == null) return;
        if (data.Get("appearance").As<Resource>() != null) instance.MaterialOverride = HasRegions(data) ? null : base_override(instance);
        update_lod(instance); var skeleton = instance.Get("growth_skeleton").As<Skeleton3D>(); if (skeleton != null && !GodotObject.IsInstanceValid(skeleton)) skeleton = null;
        var gpu = instance.Get("gpu").As<RefCounted>(); bool skinning = skeleton != null && data.Get("source_skin").As<Skin>() != null && data.Get("source_weights").AsGodotArray().Count > 0 && data.Get("rigid_bone").AsInt32() < 0;
        bool useGpu = DisplayServer.GetName() != "headless" && data.Get("roots").AsGodotArray().Count >= Get(data.Get("rendering").AsGodotDictionary(), "gpu_threshold", 3000).AsInt32() && _gpu.supports(data) && (skinning || data.Get("motion_guides").AsGodotDictionary().Count > 0);
        if (data.Get("gpu_motion").AsBool() && !useGpu && instance.Mesh != null) for (int surface = 0; surface < instance.Mesh.GetSurfaceCount(); surface++) instance.SetSurfaceOverrideMaterial(surface, null);
        data.Set("gpu_motion", useGpu); int rigidBone = data.Get("rigid_bone").AsInt32();
        GArray Poses(Skeleton3D rig) { var poses = new GArray(); for (int i = 0; i < rig.GetBoneCount(); i++) poses.Add(rig.GetBoneGlobalPose(i)); return poses; }
        if (useGpu)
        {
            if (skeleton != null) instance.GlobalTransform = rigidBone >= 0 && rigidBone < skeleton.GetBoneCount() ? skeleton.GlobalTransform * skeleton.GetBoneGlobalPose(rigidBone) * data.Get("rigid_offset").AsTransform3D() : skeleton.GlobalTransform;
            if (skinning)
            {
                long key = Hash(new GArray { Poses(skeleton!), data.Get("source_points") });
                if (key != instance.Get("gpu_bones_key").AsInt64() || instance.Get("gpu_points").AsVector3Array().Length == 0) { instance.Set("gpu_bones_key", key); instance.Set("gpu_points", _geometry.posed_points(data, skeleton)); }
            }
            else instance.Set("gpu_points", data.Get("source_points"));
            _gpu.update(gpu, instance, instance.Get("gpu_points").AsVector3Array(), skinning); instance.Mesh = _geometry.render(data, Array.Empty<Vector3>()); _gpu.bind_regions(gpu, instance, true); return;
        }
        instance.CustomAabb = new Aabb();
        void Bind() { if (HasRegions(data)) _gpu.bind_regions(gpu, instance, false); }
        if (skeleton == null) { instance.Mesh = _geometry.render(data, Array.Empty<Vector3>()); Bind(); return; }
        if (rigidBone >= 0 && rigidBone < skeleton.GetBoneCount()) { instance.GlobalTransform = skeleton.GlobalTransform * skeleton.GetBoneGlobalPose(rigidBone) * data.Get("rigid_offset").AsTransform3D(); instance.Mesh = _geometry.render(data, Array.Empty<Vector3>()); Bind(); return; }
        long poseKey = Hash(new GArray { Poses(skeleton), data.Get("revision"), data.Get("settings"), data.Get("groom_enabled"), data.Get("motion_guides"), data.Get("lod_upper"), data.Get("lod_detail"), data.Get("render_final") }); instance.GlobalTransform = skeleton.GlobalTransform;
        if (poseKey == instance.Get("pose_signature").AsInt64()) { Bind(); return; }
        instance.Set("pose_signature", poseKey); instance.Mesh = _geometry.render(data, _geometry.posed_points(data, skeleton)); Bind();
    }
}
