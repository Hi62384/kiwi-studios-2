using Godot;
using System;
using System.Collections.Generic;

public partial class CompositeLayer : Resource
{
    public enum Kind { Image, Solid, Video, Cgi, Vfx, Text, Shape, Mask, Adjustment, Group, LinkedComposition }
    public enum Blend { Over, Under, In, Out, Atop, Add, Subtract, Multiply, Screen, Difference, Minimum, Maximum, Crossfade }
    [Export] public string id { get; set; } = Guid.NewGuid().ToString("N");
    [Export] public string name { get; set; } = "Layer";
    [Export] public int kind { get; set; }
    [Export] public string parent_id { get; set; } = "";
    [Export] public bool visible { get; set; } = true;
    [Export] public bool locked { get; set; }
    [Export(PropertyHint.Range, "0,1,0.001")] public double opacity { get; set; } = 1;
    [Export] public int blend_mode { get; set; }
    [Export] public Vector2 position { get; set; } = new(640, 360);
    [Export] public double rotation { get; set; }
    [Export] public Vector2 scale { get; set; } = Vector2.One;
    [Export] public Vector2 anchor { get; set; } = new(.5f, .5f);
    [Export] public string source_path { get; set; } = "";
    [Export] public Texture2D? source_image { get; set; }
    [Export] public Color color { get; set; } = Colors.White;
    [Export] public string mask_id { get; set; } = "";
    [Export] public string processing_graph_id { get; set; } = "";
    [Export] public double start_time { get; set; }
    [Export] public double end_time { get; set; } = -1;
    [Export] public double source_time_offset { get; set; }
    [Export] public double playback_speed { get; set; } = 1;
    [Export] public Godot.Collections.Array<Godot.Collections.Dictionary> effects { get; set; } = new();
    [Export] public Godot.Collections.Dictionary settings { get; set; } = new();
    [Export] public Godot.Collections.Array<Resource> children { get; set; } = new();

    public string[] validate() => validate_resource(this);
    public string[] validate_resource(Resource layer)
    {
        var errors = new List<string>();
        string layerId = layer.Get("id").AsString(), layerName = layer.Get("name").AsString();
        int layerKind = layer.Get("kind").AsInt32();
        double alpha = layer.Get("opacity").AsDouble(), angle = layer.Get("rotation").AsDouble();
        Vector2 location = layer.Get("position").AsVector2(), size = layer.Get("scale").AsVector2();
        double start = layer.Get("start_time").AsDouble(), end = layer.Get("end_time").AsDouble(), offset = layer.Get("source_time_offset").AsDouble(), speed = layer.Get("playback_speed").AsDouble();
        string path = layer.Get("source_path").AsString(), graph = layer.Get("processing_graph_id").AsString();
        if (layerId.Length == 0 || layerName.Trim().Length == 0) errors.Add("Every compositing layer needs an ID and name.");
        if (!double.IsFinite(alpha) || alpha < 0 || alpha > 1 || !double.IsFinite(angle) || !location.IsFinite() || !size.IsFinite() || MathF.Abs(size.X) < .000001f || MathF.Abs(size.Y) < .000001f)
            errors.Add("Layer opacity and transform values are invalid.");
        if (!double.IsFinite(start) || !double.IsFinite(end) || !double.IsFinite(offset) || !double.IsFinite(speed) || start < 0 || end >= 0 && end < start || offset < 0 || speed <= 0)
            errors.Add("Layer timing values must be finite, clip ends cannot precede starts, and playback speed must be positive.");
        if (layerKind == (int)Kind.Image && layer.Get("source_image").AsGodotObject() == null && path.Length == 0 && graph.Length == 0) errors.Add(layerName + " has no image source.");
        if (layerKind == (int)Kind.Video && path.Length == 0) errors.Add(layerName + " has no video footage source.");
        if (layerKind == (int)Kind.LinkedComposition && path.Length == 0) errors.Add(layerName + " has no linked composition resource.");
        if (graph.Length > 0 && (layerKind < 0 || layerKind > 10 || layerKind is 8 or 9)) errors.Add(layerName + " cannot use a source processing graph.");
        Color tint = layer.Get("color").AsColor();
        if (layerKind == (int)Kind.Solid && (!float.IsFinite(tint.R) || !float.IsFinite(tint.G) || !float.IsFinite(tint.B) || !float.IsFinite(tint.A))) errors.Add(layerName + " has an invalid solid color.");
        return errors.ToArray();
    }
}
