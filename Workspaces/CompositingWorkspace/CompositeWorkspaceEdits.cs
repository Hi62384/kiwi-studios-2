using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using Array = Godot.Collections.Array;

public partial class CompositeWorkspaceEdits : RefCounted
{
    private static Resource? _clipboard;
    private static string _clipboardRoot = "";
    private readonly CompositingDocument _documents = new();
    private static string Text(Resource value, string property) => value.Get(property).AsString();
    private static Settings Result(bool changed, string selected, string message) => new() { ["changed"] = changed, ["selected_id"] = selected, ["message"] = message };
    private static Resource? FindGraph(Resource document, string id)
    {
        foreach (Variant value in document.Get("graphs").AsGodotArray())
        { var graph = value.As<Resource>(); if (graph != null && Text(graph, "id") == id) return graph; }
        return null;
    }
    private static Dictionary<string, string> Hierarchy(Resource document, string root)
    {
        var ids = new Dictionary<string, string> { [root] = Guid.NewGuid().ToString("N") }; bool expanded = true;
        while (expanded)
        {
            expanded = false;
            foreach (Variant value in document.Get("layers").AsGodotArray())
            {
                var layer = value.As<Resource>(); if (layer == null) continue;
                string id = Text(layer, "id");
                if (ids.ContainsKey(Text(layer, "parent_id")) && !ids.ContainsKey(id)) { ids[id] = Guid.NewGuid().ToString("N"); expanded = true; }
            }
        }
        return ids;
    }
    private static string Remap(Dictionary<string, string> map, string id, bool preserveExternal) => map.TryGetValue(id, out string? replacement) ? replacement : preserveExternal ? id : "";

    public string clone_graph(Resource destination, Resource original, Settings layerIds)
    {
        var copy = (Resource)original.Duplicate(true); string copyId = Guid.NewGuid().ToString("N");
        copy.Set("id", copyId); copy.Set("name", Text(copy, "name") + " Copy");
        var nodeIds = new Dictionary<string, string>();
        foreach (Variant value in copy.Get("nodes").AsGodotArray())
        {
            var node = value.As<Resource>(); if (node == null) continue;
            string id = Guid.NewGuid().ToString("N"); nodeIds[Text(node, "id")] = id; node.Set("id", id);
            if (Text(node, "kind") == "Layer Source")
            {
                var settings = node.Get("settings").AsGodotDictionary();
                if (settings.TryGetValue("layer_id", out var owner) && layerIds.TryGetValue(owner.AsString(), out var replacement)) settings["layer_id"] = replacement;
            }
        }
        foreach (Variant value in copy.Get("connections").AsGodotArray())
        {
            var edge = value.As<Resource>(); if (edge == null) continue;
            edge.Set("from_node", Remap(nodeIds, Text(edge, "from_node"), true)); edge.Set("to_node", Remap(nodeIds, Text(edge, "to_node"), true));
        }
        copy.Set("output_node", Remap(nodeIds, Text(copy, "output_node"), true));
        var graphs = destination.Get("graphs").AsGodotArray(); graphs.Add(copy); destination.Set("graphs", graphs); return copyId;
    }

    private Settings CopyHierarchy(Resource source, Resource destination, string root, bool paste)
    {
        var map = Hierarchy(source, root); var layerMap = new Settings(); foreach (var pair in map) layerMap[pair.Key] = pair.Value;
        var copies = new List<Resource>();
        foreach (Variant value in source.Get("layers").AsGodotArray())
        {
            var original = value.As<Resource>(); if (original == null || !map.ContainsKey(Text(original, "id"))) continue;
            var copy = (Resource)original.Duplicate(true); copy.Set("id", map[Text(original, "id")]);
            if (!paste) copy.Set("name", Text(copy, "name") + " Copy");
            copy.Set("parent_id", Remap(map, Text(original, "parent_id"), !paste)); copy.Set("mask_id", Remap(map, Text(original, "mask_id"), !paste));
            var graph = FindGraph(source, Text(original, "processing_graph_id"));
            copy.Set("processing_graph_id", graph == null ? "" : clone_graph(destination, graph, layerMap)); copies.Add(copy);
        }
        var destinationLayers = destination.Get("layers").AsGodotArray(); foreach (var copy in copies) destinationLayers.Add(copy); destination.Set("layers", destinationLayers);
        var byId = new Dictionary<string, Resource>(); foreach (var copy in copies) byId[Text(copy, "id")] = copy;
        foreach (var copy in copies)
        {
            var remappedChildren = new Godot.Collections.Array<Resource>();
            foreach (Variant childValue in copy.Get("children").AsGodotArray())
            {
                var child = childValue.As<Resource>(); if (child == null) continue;
                if (map.TryGetValue(Text(child, "id"), out var newId) && byId.TryGetValue(newId, out var newChild)) remappedChildren.Add(newChild);
                else if (!paste) remappedChildren.Add(child);
            }
            copy.Set("children", remappedChildren);
        }
        var tracks = new List<Settings>();
        foreach (Variant value in source.Get("animation").AsGodotArray())
        {
            var track = value.AsGodotDictionary(); string owner = track.TryGetValue("layer_id", out var found) ? found.AsString() : "";
            if (!map.TryGetValue(owner, out string? newOwner)) continue;
            var copy = track.Duplicate(true); copy["layer_id"] = newOwner; tracks.Add(copy);
        }
        var destinationTracks = destination.Get("animation").AsGodotArray(); foreach (var track in tracks) destinationTracks.Add(track); destination.Set("animation", destinationTracks);
        return Result(true, map[root], paste ? "Paste layer hierarchy" : "Duplicate layer hierarchy");
    }

    public Settings duplicate_layer(Resource document, string selected)
    {
        if (_documents.layer_resource(document, selected) == null) return Result(false, selected, "");
        return CopyHierarchy(document, document, selected, false);
    }
    public Settings copy_layer(Resource document, string selected)
    {
        var layer = _documents.layer_resource(document, selected); if (layer == null) return Result(false, selected, "");
        _clipboard = (Resource)document.Duplicate(true); _clipboardRoot = selected; return Result(false, selected, "Copied " + Text(layer, "name"));
    }
    public Settings paste_layer(Resource document)
    {
        if (_clipboard == null) return Result(false, "", "Copy a layer first.");
        return CopyHierarchy(_clipboard, document, _clipboardRoot, true);
    }
    public Settings delete_layer(Resource document, string selected)
    {
        if (_documents.layer_resource(document, selected) == null) return Result(false, selected, "");
        var remove = Hierarchy(document, selected); var layers = document.Get("layers").AsGodotArray();
        for (int i = layers.Count - 1; i >= 0; i--) if (layers[i].As<Resource>() is { } layer && remove.ContainsKey(Text(layer, "id"))) layers.RemoveAt(i);
        document.Set("layers", layers);
        var tracks = document.Get("animation").AsGodotArray();
        for (int i = tracks.Count - 1; i >= 0; i--)
        { var track = tracks[i].AsGodotDictionary(); if (track.TryGetValue("layer_id", out var owner) && remove.ContainsKey(owner.AsString())) tracks.RemoveAt(i); }
        document.Set("animation", tracks);
        if (remove.ContainsKey(Text(document, "solo_layer_id"))) document.Set("solo_layer_id", "");
        return Result(true, "", "Delete layer");
    }
    public Settings move_layer(Resource document, string selected, int direction)
    {
        var layer = _documents.layer_resource(document, selected); if (layer == null) return Result(false, selected, "");
        var layers = document.Get("layers").AsGodotArray(); int index = layers.IndexOf(layer), target = index + direction;
        if (target < 0 || target >= layers.Count || Text(layers[target].As<Resource>(), "parent_id") != Text(layer, "parent_id")) return Result(false, selected, "");
        layers.RemoveAt(index); layers.Insert(target, layer); document.Set("layers", layers); return Result(true, selected, "Reorder layer");
    }
    public Settings group_layers(Resource document, Godot.Collections.Array<string> ids)
    {
        if (ids.Count < 2) return Result(false, "", "Select at least two layers to group.");
        var first = _documents.layer_resource(document, ids[0]); if (first == null) return Result(false, "", "");
        string parent = Text(first, "parent_id");
        foreach (string id in ids)
        { var layer = _documents.layer_resource(document, id); if (layer == null || Text(layer, "parent_id") != parent) return Result(false, "", "Group layers that share the same parent."); }
        var group = _documents.add_layer_resource(document, (int)CompositeLayer.Kind.Group, "Group"); group.Set("parent_id", parent);
        foreach (string id in ids) _documents.layer_resource(document, id)!.Set("parent_id", group.Get("id"));
        return Result(true, Text(group, "id"), "Group layers");
    }
    public Settings ungroup_layer(Resource document, string selected)
    {
        var group = _documents.layer_resource(document, selected); if (group == null || group.Get("kind").AsInt32() != (int)CompositeLayer.Kind.Group) return Result(false, selected, "");
        var layers = document.Get("layers").AsGodotArray(); string parent = Text(group, "parent_id");
        foreach (Variant value in layers) { var layer = value.As<Resource>(); if (layer != null && Text(layer, "parent_id") == selected) layer.Set("parent_id", parent); }
        layers.Remove(group); document.Set("layers", layers); return Result(true, "", "Ungroup layers");
    }
}
