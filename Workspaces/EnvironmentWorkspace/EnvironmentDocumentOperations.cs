using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentDocumentOperations : RefCounted
{
    private readonly ModelDocumentOperations _model = new();
    private readonly ModelComponentOperations _components = new();
    private readonly ModelMeshOperations _meshes = new();
    private static Settings SettingsFor(Resource source) => source.Get("component_settings").AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static bool Type(Resource value, string path)
    { var script = value.GetScript().As<Script>(); while (script != null) { if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script = script.GetBaseScript(); } return false; }
    public Resource? terrain(Resource source, string id)
    {
        var value = Get(Get(SettingsFor(source), id, new Settings()).AsGodotDictionary(), "terrain").As<Resource>(); return value != null && Type(value, "res://Workspaces/EnvironmentWorkspace/environment_terrain.gd") ? value : null;
    }
    public string component_kind(Resource source, string id) => Get(Get(SettingsFor(source), id, new Settings()).AsGodotDictionary(), "kind", "asset").AsString();
    public string[] component_geometry_errors(Resource source, Resource item) => _meshes.validate(item.Get("mesh").As<Resource>(), component_kind(source, item.Get("id").AsString()) != "terrain");
    public string[] validate(Resource source)
    {
        var errors = _model.validate(source).ToList(); int version = source.Get("version").AsInt32(); if (version != 1) errors.Add("Unsupported environment schema version: " + version);
        var climate = source.Get("climate").As<Resource>(); if (climate != null && climate.HasMethod("validate")) errors.AddRange(climate.Call("validate").AsStringArray());
        foreach (var pair in SettingsFor(source))
        {
            string id = pair.Key.AsString(); var settings = pair.Value.AsGodotDictionary(); var item = _model.component(source, id); if (item == null) errors.Add("Environment settings refer to a missing component: " + id);
            if (Get(settings, "kind", "").AsString() == "building")
            {
                var building = item != null ? Get(item.Get("parameters").AsGodotDictionary(), "architecture_source").As<Resource>() : null;
                if (building?.GetScript().As<Script>()?.ResourcePath != "res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs") errors.Add("Streamed building settings require an authored building source."); else errors.AddRange(building.Call("validate").AsStringArray());
            }
            var terrain = Get(settings, "terrain").As<Resource>(); if (terrain != null && Type(terrain, "res://Workspaces/EnvironmentWorkspace/environment_terrain.gd")) errors.AddRange(terrain.Call("validate").AsStringArray());
            var scatter = Get(settings, "scatter").As<Resource>(); if (scatter != null && Type(scatter, "res://Workspaces/EnvironmentWorkspace/environment_scatter.gd")) { errors.AddRange(scatter.Call("validate").AsStringArray()); if (this.terrain(source, scatter.Get("terrain_id").AsString()) == null) errors.Add("Scatter has a missing terrain dependency."); }
        }
        return errors.ToArray();
    }
    public Resource snapshot(Resource source)
    {
        var result = new KiwiEnvironmentDocument();
        foreach (string key in new[] { "version", "environment_id", "title", "random_seed", "preview", "preview_png", "environment_source" }) result.Set(key, source.Get(key));
        result.Set("workspace_state", source.Get("workspace_state").AsGodotDictionary().Duplicate(true)); result.Set("sunlight", source.Get("sunlight").AsGodotDictionary().Duplicate(true));
        var atmosphere = source.Get("atmosphere").As<Resource>(); result.Set("atmosphere", atmosphere != null ? atmosphere.Call("copy_reference") : default);
        var climate = source.Get("climate").As<Resource>(); result.Set("climate", climate != null ? climate.HasMethod("copy_climate") ? climate.Call("copy_climate") : Variant.From(climate.Duplicate(true)) : default);
        var components = result.Get("components").AsGodotArray(); foreach (var value in source.Get("components").AsGodotArray()) components.Add(_components.copy_component(value.As<Resource>(), false));
        var settings = SettingsFor(source); var copies = settings.Duplicate(true); result.Set("component_settings", copies);
        foreach (var pair in settings)
        {
            var original = pair.Value.AsGodotDictionary(); var copy = copies[pair.Key].AsGodotDictionary();
            foreach (string kind in new[] { "terrain", "scatter" })
                if (Get(original, kind).As<Resource>() is Resource resource && Type(resource, "res://Workspaces/EnvironmentWorkspace/environment_" + kind + ".gd")) copy[kind] = resource.Duplicate(true);
        }
        return result;
    }
    public Resource add_terrain(Resource document, Resource? settings)
    {
        var item = new KiwiModelComponent(); item.Set("id", Guid.NewGuid().ToString("N")); item.Set("title", "Terrain");
        var source = settings ?? GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_terrain.gd").New().As<Resource>(); source.Call("prepare"); item.Set("mesh", source.Call("editable_mesh")); document.Get("components").AsGodotArray().Add(item); SettingsFor(document)[item.Get("id")] = new Settings { ["kind"] = "terrain", ["terrain"] = source, ["collision"] = true }; return item;
    }
    public Resource add_group(Resource document, string name)
    {
        var item = new KiwiModelComponent(); item.Set("id", Guid.NewGuid().ToString("N")); item.Set("title", name); document.Get("components").AsGodotArray().Add(item); SettingsFor(document)[item.Get("id")] = new Settings { ["kind"] = "group" }; return item;
    }
    public Settings water_at(Resource source, Vector3 worldPoint, Transform3D environmentPose)
    {
        foreach (var value in source.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>(); string id = item.Get("id").AsString(); var terrain = this.terrain(source, id); if (terrain == null || terrain.Get("hydrology").As<Resource>() is not Resource hydrology || !_model.visible_component(source, item)) continue;
            var pose = environmentPose * _model.world_transform(source, item); if (Math.Abs(pose.Basis.Determinant()) < .000001f) continue; var result = terrain.Call("water_at", pose.AffineInverse() * worldPoint).AsGodotDictionary(); if (result.Count == 0) continue;
            Vector3 local = result["surface"].AsVector3(), bottom = pose * new Vector3(local.X, result["bottom"].AsSingle(), local.Z), surface = pose * local;
            result["local_depth"] = result["depth"]; result["local_bottom"] = result["bottom"]; result["surface"] = surface; result["depth"] = surface.DistanceTo(bottom); result["bottom"] = bottom.Y; result["bottom_position"] = bottom; result["normal"] = (pose.Basis * Vector3.Up).Normalized(); result["flow"] = pose.Basis * result["flow"].AsVector3(); result["terrain_id"] = id; result["physics"] = hydrology.Get("water_physics"); result["density"] = hydrology.Get("water_density"); result["drag"] = hydrology.Get("water_drag"); return result;
        }
        return new Settings();
    }
}
