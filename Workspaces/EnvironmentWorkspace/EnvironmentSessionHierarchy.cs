using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentSessionOperations
{
    public void duplicate_selected(RefCounted session, bool preview)
    {
        void Duplicate()
        {
            var document = Doc(session); var components = document.Get("components").AsGodotArray(); var ids = new Settings(); var copies = new List<Resource>(); var metadata = new Settings(); var selection = new HashSet<string>(Selected(session), StringComparer.Ordinal); var lookup = ModelDocumentOperations.Lookup(document);
            foreach (var value in components)
            {
                var item = value.As<Resource>(); string id = item.Get("id").AsString(), current = id; bool included = false; var visited = new HashSet<string>(StringComparer.Ordinal);
                while (visited.Add(current) && lookup.TryGetValue(current, out var ancestor)) { if (selection.Contains(current)) { included = true; break; } current = ancestor.Get("parent_id").AsString(); }
                if (!included || !_documents.editable_component(document, item)) continue;
                var copy = _components.copy_component(item, true); string newId = copy.Get("id").AsString(); ids[id] = newId; copy.Set("title", copy.Get("title").AsString() + " copy"); copies.Add(copy);
                var settings = Get(Dict(document, "component_settings"), id, new Settings()).AsGodotDictionary().Duplicate(true); metadata[newId] = settings;
                foreach (string key in new[] { "terrain", "scatter" }) if (Get(settings, key).As<Resource>() is Resource resource) settings[key] = resource.Duplicate(true);
            }
            foreach (var copy in copies)
            {
                copy.Set("parent_id", Get(ids, copy.Get("parent_id"), copy.Get("parent_id")).AsString()); components.Add(copy); string id = copy.Get("id").AsString(); var settings = metadata[id].AsGodotDictionary(); Dict(document, "component_settings")[id] = settings;
                _remap.component(copy, ids); _remap.terrain(Get(settings, "terrain").As<Resource>(), ids); var scatter = Get(settings, "scatter").As<Resource>(); if (scatter != null) scatter.Set("terrain_id", Get(ids, scatter.Get("terrain_id"), scatter.Get("terrain_id")).AsString());
            }
            var selected = Selected(session); string[] roots = selected.ToArray(); selected.Clear(); foreach (string id in roots) if (ids.ContainsKey(id)) selected.Add(ids[id].AsString());
        }
        if (preview) { session.Call("begin"); Duplicate(); Changed(session); } else Action(session, "Duplicate environment components", Duplicate);
    }
    public string delete_selected(RefCounted session)
    {
        Action(session, "Delete environment components", () =>
        {
            var document = Doc(session); var components = document.Get("components").AsGodotArray(); var selected = new HashSet<string>(Selected(session), StringComparer.Ordinal); var removed = new Settings();
            foreach (var value in components) { var item = value.As<Resource>(); if (selected.Contains(item.Get("id").AsString()) && _documents.editable_component(document, item)) removed[item.Get("id")] = true; }
            foreach (var id in removed.Keys.ToArray())
            {
                var item = _documents.component(document, id.AsString()); var authored = item != null ? Get(Dict(item, "parameters"), "world_source").As<Resource>() : null;
                if (authored?.GetScript().As<Script>()?.ResourcePath == "res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs" && authored.Get("owned_terrain_id").AsString().Length > 0) removed[authored.Get("owned_terrain_id")] = true;
            }
            foreach (var value in components) { var item = value.As<Resource>(); var parameters = Dict(item, "parameters"); if (Get(parameters, "world_generated", false).AsBool() && removed.ContainsKey(Get(parameters, "world_owner", ""))) removed[item.Get("id")] = true; }
            GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd").Call("remove_for_owners", session, removed);
            foreach (var value in components)
            {
                var item = value.As<Resource>(); if (removed.ContainsKey(item.Get("parent_id")) && !removed.ContainsKey(item.Get("id"))) { item.Set("transform", _documents.world_transform(document, item)); item.Set("parent_id", ""); }
            }
            var retained = components.Duplicate(); retained.Clear(); foreach (var value in components) { var item = value.As<Resource>(); if (removed.ContainsKey(item.Get("id"))) Dict(document, "component_settings").Remove(item.Get("id")); else retained.Add(item); }
            document.Set("components", retained); Selected(session).Clear(); session.Set("elements", Array.Empty<int>());
        }); return "";
    }
}
