using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class EnvironmentSessionOperations
{
    private static bool ScriptType(Resource value, string path)
    { var script = value.GetScript().As<Script>(); while (script != null) { if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script = script.GetBaseScript(); } return false; }
    private static Godot.Collections.Array<string> Selected(RefCounted session) => session.Get("selected").AsGodotArray<string>();
    private static void SelectOnly(RefCounted session, string id) { var selected = Selected(session); selected.Clear(); selected.Add(id); }
    public Resource? environment(RefCounted session) => ScriptType(Doc(session), "res://Workspaces/EnvironmentWorkspace/environment_document.gd") ? Doc(session) : null;
    public void commit(RefCounted session, string label)
    {
        if (Dict(session, "_gesture").Count > 0) GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd").Call("refresh_links", session); _history.commit(session, label);
    }
    public long signature(Resource source)
    {
        long basis = _history._signature(source); if (!ScriptType(source, "res://Workspaces/EnvironmentWorkspace/environment_document.gd")) return basis; var fields = new GArray();
        foreach (var pair in Dict(source, "component_settings"))
        {
            var settings = pair.Value.AsGodotDictionary(); var terrain = Get(settings, "terrain").As<Resource>(); var copy = settings.Duplicate(); copy.Remove("terrain"); copy.Remove("scatter");
            fields.Add(new GArray { pair.Key, copy, terrain != null && ScriptType(terrain, "res://Workspaces/EnvironmentWorkspace/environment_terrain.gd") ? terrain.Call("signature") : 0 });
            var scatter = Get(settings, "scatter").As<Resource>(); if (scatter != null && ScriptType(scatter, "res://Workspaces/EnvironmentWorkspace/environment_scatter.gd")) fields.Add(scatter.Call("signature"));
        }
        var climate = source.Get("climate").As<Resource>(); return unchecked((uint)GD.Hash(new GArray { basis, fields, source.Get("title"), source.Get("sunlight"), source.Get("atmosphere"), source.Get("environment_source"), source.Get("random_seed"), climate != null && climate.HasMethod("signature") ? climate.Call("signature") : 0 }));
    }
    public Resource add_terrain(RefCounted session)
    {
        Resource result = null!; Action(session, "Add terrain", () => { result = Doc(session).Call("add_terrain").As<Resource>(); SelectOnly(session, result.Get("id").AsString()); }); return result;
    }
    public Resource add_group(RefCounted session, string name)
    {
        Resource result = null!; Action(session, "Add environment group", () => { result = Doc(session).Call("add_group", name).As<Resource>(); SelectOnly(session, result.Get("id").AsString()); }); return result;
    }
    public Resource? selected_environment(RefCounted session)
    {
        var selected = Selected(session); if (selected.Count == 0) return null; var source = Doc(session); var lookup = ModelDocumentOperations.Lookup(source); var selection = new HashSet<string>(selected, StringComparer.Ordinal); var included = new HashSet<string>(StringComparer.Ordinal);
        foreach (var pair in lookup)
        {
            string current = pair.Key; var visited = new HashSet<string>(StringComparer.Ordinal);
            while (visited.Add(current) && lookup.TryGetValue(current, out var item)) { if (selection.Contains(current)) { included.Add(pair.Key); break; } current = item.Get("parent_id").AsString(); }
        }
        foreach (string id in included.ToArray())
        {
            var scatter = Scatter(session, id); if (scatter != null) included.Add(scatter.Get("terrain_id").AsString());
            if (lookup.TryGetValue(id, out var item) && Get(Dict(item, "parameters"), "world_source").As<Resource>() is Resource world && world.GetScript().As<Script>()?.ResourcePath == "res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs")
            { string terrainId = world.Get("terrain_id").AsString(); if (source.Call("terrain", terrainId).As<Resource>() != null) included.Add(terrainId); }
        }
        var result = source.Call("snapshot").As<Resource>(); var components = result.Get("components").AsGodotArray(); var retained = components.Duplicate(); retained.Clear();
        foreach (var value in components)
        {
            var item = value.As<Resource>(); string id = item.Get("id").AsString(); if (!included.Contains(id)) { Dict(result, "component_settings").Remove(id); continue; }
            string parent = item.Get("parent_id").AsString(); if (parent.Length > 0 && !included.Contains(parent)) { item.Set("transform", _documents.world_transform(source, lookup[id])); item.Set("parent_id", ""); } retained.Add(item);
        }
        result.Set("components", retained); result.Set("environment_id", Guid.NewGuid().ToString("N")); result.Set("title", session.Call("primary").As<Resource>()?.Get("title").AsString() ?? "Environment component"); result.Set("workspace_state", new Settings()); result.Set("environment_source", ""); result.Set("atmosphere", default(Variant)); result.Set("sunlight", new Settings { ["enabled"] = false }); return result;
    }
    public string insert_environment(RefCounted session, Resource? source, Vector3 origin)
    {
        if (source == null || source.Call("validate").AsStringArray().Length > 0) return "The environment component is invalid.";
        Action(session, "Insert reusable environment", () =>
        {
            var copy = source.Call("snapshot").As<Resource>(); var document = Doc(session); var root = document.Call("add_group", source.Get("title")).As<Resource>(); var transform = root.Get("transform").AsTransform3D(); transform.Origin = origin; root.Set("transform", transform); var ids = new Settings();
            var components = copy.Get("components").AsGodotArray(); foreach (var value in components) ids[value.As<Resource>().Get("id")] = Guid.NewGuid().ToString("N");
            foreach (var value in components)
            {
                var item = value.As<Resource>(); string old = item.Get("id").AsString(); item.Set("id", ids[old].AsString()); item.Set("parent_id", Get(ids, item.Get("parent_id"), root.Get("id")).AsString()); document.Get("components").AsGodotArray().Add(item);
                var metadata = Get(Dict(copy, "component_settings"), old, new Settings { ["kind"] = "group" }).AsGodotDictionary(); Dict(document, "component_settings")[item.Get("id")] = metadata; _remap.component(item, ids); _remap.terrain(Get(metadata, "terrain").As<Resource>(), ids);
                var scatter = Get(metadata, "scatter").As<Resource>(); if (scatter != null) scatter.Set("terrain_id", Get(ids, scatter.Get("terrain_id"), scatter.Get("terrain_id")).AsString());
            }
            SelectOnly(session, root.Get("id").AsString());
        }); return "";
    }
}
