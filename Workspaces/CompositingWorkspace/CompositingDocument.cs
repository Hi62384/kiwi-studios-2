using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Array = Godot.Collections.Array;
using Dictionary = Godot.Collections.Dictionary;

public partial class CompositingDocument : Resource
{
    private sealed class TextureStamp { public bool Dirty = true; public long Hash; }
    private static readonly ConditionalWeakTable<Texture2D, TextureStamp> TextureStamps = new();
    private static long TextureSignature(Texture2D texture)
    {
        var stamp = TextureStamps.GetValue(texture, value =>
        {
            var created = new TextureStamp(); value.Changed += () => created.Dirty = true; return created;
        });
        // Mutable ImageTexture.Update does not reliably emit Resource.Changed.
        if (texture is not CompressedTexture2D) stamp.Dirty = true;
        if (!stamp.Dirty) return stamp.Hash;
        using var image = texture.GetImage();
        stamp.Hash = image == null ? GD.Hash(texture.ResourcePath) : GD.Hash(new Array { image.GetSize(), (int)image.GetFormat(), image.GetData() });
        stamp.Dirty = false; return stamp.Hash;
    }
    [Export] public int version { get; set; } = 1;
    [Export] public string document_id { get; set; } = Guid.NewGuid().ToString("N");
    [Export] public string title { get; set; } = "Untitled Composition";
    [Export] public Vector2I canvas_size { get; set; } = new(1920, 1080);
    [Export] public double pixel_aspect_ratio { get; set; } = 1;
    [Export] public double frame_rate { get; set; } = 24;
    [Export] public double duration { get; set; } = 10;
    [Export(PropertyHint.Enum, "Linear sRGB")] public int working_color_space { get; set; }
    [Export] public Dictionary input_color_settings { get; set; } = new();
    [Export] public Dictionary output_color_settings { get; set; } = new() { ["transform"] = "sRGB" };
    [Export] public Godot.Collections.Array<Resource> layers { get; set; } = new();
    [Export] public Godot.Collections.Array<Resource> graphs { get; set; } = new();
    [Export] public string active_graph_id { get; set; } = "";
    [Export] public string solo_layer_id { get; set; } = "";
    [Export] public Godot.Collections.Array<string> media_references { get; set; } = new();
    [Export] public Godot.Collections.Array<Dictionary> render_references { get; set; } = new();
    [Export] public Godot.Collections.Array<Resource> masks { get; set; } = new();
    [Export] public Godot.Collections.Array<Dictionary> animation { get; set; } = new();
    [Export] public Dictionary processing_settings { get; set; } = new() { ["precision"] = "float32", ["tile_size"] = 256, ["cache"] = true };
    [Export] public Dictionary render_settings { get; set; } = new() { ["transparent"] = true, ["quality"] = "Preview" };
    [Export] public Dictionary cache_references { get; set; } = new();
    [Export] public Dictionary workspace_state { get; set; } = new();

    public Resource? layer(string id) => layer_resource(this, id);
    public string[] validate() => validate_resource(this);
    public long signature() => signature_resource(this);
    public Resource add_layer(int kind, string name = "Layer") => add_layer_resource(this, kind, name);
    public bool has_layer_track(string layer_id, string property) => TrackIndex(this, layer_id, property) >= 0;
    public bool set_layer_key(string layer_id, string property, double time, Variant value) => set_layer_key_resource(this, layer_id, property, time, value);
    public Variant sample_layer_value(string layer_id, string property, double time, Variant base_value) => sample_layer_value_resource(this, layer_id, property, time, base_value);
    private static string Text(Resource resource, string property) => resource.Get(property).AsString();
    private static Variant Value(Dictionary data, string property, Variant fallback = default) => data.TryGetValue(property, out var value) ? value : fallback;

    public Resource? layer_resource(Resource document, string id)
    {
        foreach (Variant value in document.Get("layers").AsGodotArray())
        { var item = value.As<Resource>(); if (item != null && Text(item, "id") == id) return item; }
        return null;
    }

    public Resource add_layer_resource(Resource document, int kind, string name = "Layer")
    {
        var item = new CompositeLayer { kind = kind, name = name, position = (Vector2)document.Get("canvas_size").AsVector2I() * .5f };
        var list = document.Get("layers").AsGodotArray(); list.Add(item); document.Set("layers", list); return item;
    }

    public string[] validate_resource(Resource document)
    {
        var errors = new List<string>(); var ids = new HashSet<string>(); var parents = new Dictionary<string, string>();
        if (document.Get("version").AsInt32() != 1) errors.Add("Unsupported compositing document version.");
        if (Text(document, "document_id").Length == 0 || Text(document, "title").Trim().Length == 0) errors.Add("A composition needs a document ID and title.");
        Vector2I size = document.Get("canvas_size").AsVector2I(); double aspect = document.Get("pixel_aspect_ratio").AsDouble();
        if (size.X < 1 || size.Y < 1 || size.X > 16384 || size.Y > 16384 || !double.IsFinite(aspect) || aspect <= 0) errors.Add("Canvas size and pixel aspect ratio are invalid.");
        double fps = document.Get("frame_rate").AsDouble(), length = document.Get("duration").AsDouble();
        if (!double.IsFinite(fps) || fps <= 0 || fps > 240 || !double.IsFinite(length) || length <= 0) errors.Add("Composition frame rate and duration are invalid.");
        using var layerRules = new CompositeLayer(); using var graphRules = new CompositeGraph();
        foreach (Variant value in document.Get("layers").AsGodotArray())
        {
            var item = value.As<Resource>(); if (item == null) { errors.Add("A compositing layer is missing."); continue; }
            string id = Text(item, "id"); if (!ids.Add(id)) errors.Add("Layer IDs must be unique.");
            parents[id] = Text(item, "parent_id"); errors.AddRange(layerRules.validate_resource(item));
        }
        foreach (Variant value in document.Get("layers").AsGodotArray())
        {
            var item = value.As<Resource>(); if (item == null) continue;
            string parent = Text(item, "parent_id");
            if (parent.Length > 0 && !ids.Contains(parent)) errors.Add(Text(item, "name") + " has a missing parent.");
        }
        foreach (string id in ids)
        {
            var seen = new HashSet<string>(); string current = id;
            while (current.Length > 0 && parents.TryGetValue(current, out string? parent))
            {
                if (!seen.Add(current)) { errors.Add("Layer parenting cannot contain cycles."); goto ParentsChecked; }
                current = parent;
            }
        }
        ParentsChecked:
        foreach (Variant value in document.Get("graphs").AsGodotArray())
        { var graph = value.As<Resource>(); if (graph == null) errors.Add("A compositing graph is missing."); else errors.AddRange(graphRules.validate_resource(graph)); }
        return errors.ToArray();
    }

    public long signature_resource(Resource document)
    {
        var layerData = new Array(); var graphData = new Array();
        string[] layerFields = { "id", "name", "kind", "parent_id", "visible", "locked", "opacity", "blend_mode", "position", "rotation", "scale", "anchor", "source_path", "source_image", "color", "mask_id", "processing_graph_id", "start_time", "end_time", "source_time_offset", "playback_speed", "effects", "settings", "children" };
        foreach (Variant value in document.Get("layers").AsGodotArray())
        {
            var item = value.As<Resource>(); if (item == null) { layerData.Add(default(Variant)); continue; }
            var data = new Array();
            foreach (string field in layerFields)
            {
                Variant fieldValue = item.Get(field);
                if (field == "source_image" && fieldValue.AsGodotObject() is Texture2D texture) data.Add(TextureSignature(texture));
                else if (field == "children")
                {
                    var childIds = new Array(); foreach (Variant child in fieldValue.AsGodotArray()) childIds.Add(child.As<Resource>()?.Get("id") ?? default);
                    data.Add(childIds);
                }
                else data.Add(fieldValue);
            }
            layerData.Add(data);
        }
        foreach (Variant value in document.Get("graphs").AsGodotArray())
        {
            var graph = value.As<Resource>(); if (graph == null) { graphData.Add(default(Variant)); continue; }
            var nodeData = new Array(); var edgeData = new Array();
            foreach (Variant nodeValue in graph.Get("nodes").AsGodotArray())
            {
                var node = nodeValue.As<Resource>(); if (node == null) continue;
                nodeData.Add(new Array { node.Get("id"), node.Get("kind"), node.Get("position"), node.Get("settings"), node.Get("exposed") });
            }
            foreach (Variant edgeValue in graph.Get("connections").AsGodotArray())
            {
                var edge = edgeValue.As<Resource>(); if (edge == null) continue;
                edgeData.Add(new Array { edge.Get("from_node"), edge.Get("from_port"), edge.Get("to_node"), edge.Get("to_port") });
            }
            graphData.Add(new Array { graph.Get("id"), graph.Get("name"), nodeData, edgeData, graph.Get("output_node") });
        }
        var state = new Array();
        foreach (string property in new[] { "version", "document_id", "title", "canvas_size", "pixel_aspect_ratio", "frame_rate", "duration", "working_color_space", "input_color_settings", "output_color_settings" }) state.Add(document.Get(property));
        state.Add(layerData); state.Add(graphData);
        foreach (string property in new[] { "active_graph_id", "solo_layer_id", "media_references", "render_references", "masks", "animation", "processing_settings", "render_settings" }) state.Add(document.Get(property));
        return GD.Hash(state);
    }

    private static int TrackIndex(Resource document, string layerId, string property)
    {
        var tracks = document.Get("animation").AsGodotArray();
        for (int i = 0; i < tracks.Count; i++) { var track = tracks[i].AsGodotDictionary(); if (Value(track, "layer_id", "").AsString() == layerId && Value(track, "property", "").AsString() == property) return i; }
        return -1;
    }
    public bool has_layer_track_resource(Resource document, string layerId, string property) => TrackIndex(document, layerId, property) >= 0;
    public bool set_layer_key_resource(Resource document, string layerId, string property, double time, Variant value)
    {
        if (layer_resource(document, layerId) == null || property is not ("position" or "rotation" or "scale" or "opacity") || !double.IsFinite(time)) return false;
        time = Math.Clamp(time, 0, document.Get("duration").AsDouble());
        var tracks = document.Get("animation").AsGodotArray(); int index = TrackIndex(document, layerId, property);
        if (index < 0) { tracks.Add(new Dictionary { ["layer_id"] = layerId, ["property"] = property, ["keys"] = new Array() }); index = tracks.Count - 1; }
        var track = tracks[index].AsGodotDictionary(); var keys = Value(track, "keys", new Array()).AsGodotArray(); bool replaced = false;
        for (int i = 0; i < keys.Count; i++)
        {
            double existing = Value(keys[i].AsGodotDictionary(), "time", -1d).AsDouble();
            if (Math.Abs(existing - time) < Math.Max(.00001 * Math.Abs(existing), .00001)) { keys[i] = new Dictionary { ["time"] = time, ["value"] = value }; replaced = true; break; }
        }
        if (!replaced) keys.Add(new Dictionary { ["time"] = time, ["value"] = value });
        var sorted = new List<Dictionary>(); foreach (Variant key in keys) sorted.Add(key.AsGodotDictionary());
        sorted.Sort((a, b) => Value(a, "time", 0d).AsDouble().CompareTo(Value(b, "time", 0d).AsDouble()));
        keys.Clear(); foreach (var key in sorted) keys.Add(key);
        track["keys"] = keys; tracks[index] = track; document.Set("animation", tracks); return true;
    }

    public Variant sample_layer_value_resource(Resource document, string layerId, string property, double time, Variant baseValue)
    {
        int index = TrackIndex(document, layerId, property); if (index < 0) return baseValue;
        var keys = Value(document.Get("animation").AsGodotArray()[index].AsGodotDictionary(), "keys", new Array()).AsGodotArray();
        if (keys.Count == 0) return baseValue;
        if (time <= Value(keys[0].AsGodotDictionary(), "time", 0d).AsDouble()) return Value(keys[0].AsGodotDictionary(), "value", baseValue);
        for (int i = 1; i < keys.Count; i++)
        {
            var left = keys[i - 1].AsGodotDictionary(); var right = keys[i].AsGodotDictionary();
            double leftTime = Value(left, "time", 0d).AsDouble(), rightTime = Value(right, "time", leftTime).AsDouble();
            if (time > rightTime) continue;
            double amount = rightTime == leftTime ? 0 : (time - leftTime) / (rightTime - leftTime);
            Variant a = Value(left, "value", baseValue), b = Value(right, "value", baseValue);
            if (a.VariantType == Variant.Type.Vector2 && b.VariantType == Variant.Type.Vector2) return a.AsVector2().Lerp(b.AsVector2(), (float)amount);
            if (a.VariantType == Variant.Type.Vector3 && b.VariantType == Variant.Type.Vector3) return a.AsVector3().Lerp(b.AsVector3(), (float)amount);
            if (a.VariantType == Variant.Type.Color && b.VariantType == Variant.Type.Color) return a.AsColor().Lerp(b.AsColor(), (float)amount);
            if (a.VariantType is Variant.Type.Float or Variant.Type.Int) return a.AsDouble() + (b.AsDouble() - a.AsDouble()) * amount;
            return amount < .5 ? a : b;
        }
        return Value(keys[keys.Count - 1].AsGodotDictionary(), "value", baseValue);
    }
}
