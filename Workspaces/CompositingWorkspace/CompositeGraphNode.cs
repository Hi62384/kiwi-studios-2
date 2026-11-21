using Godot;
using System;

public partial class CompositeGraphNode : Resource
{
    [Export] public string id { get; set; } = Guid.NewGuid().ToString("N");
    [Export(PropertyHint.Enum, "Image Source,Solid Color,Layer Source,Over,Merge,Mask,Blur,Chroma Key,Luma Key,Color Grade,Output,Alpha Extract,Depth Compare")]
    public string kind { get; set; } = "Image Source";
    [Export] public Vector2 position { get; set; }
    [Export] public Godot.Collections.Dictionary settings { get; set; } = new();
    [Export] public bool exposed { get; set; }

    public StringName port_type(string nodeKind, string port) => PortType(nodeKind, port);
    private static string PortType(string nodeKind, string port) => nodeKind switch
    {
        "Image Source" or "Layer Source" or "Solid Color" or "Output" => port == "image" ? "image" : "",
        "Over" or "Merge" => port is "foreground" or "background" or "image" ? "image" : "",
        "Mask" or "Alpha Extract" => port == "image" ? "image" : port == "mask" ? "mask" : "",
        "Blur" or "Chroma Key" or "Luma Key" or "Color Grade" => port is "image" or "output" ? "image" : "",
        "Depth Compare" => port == "image" ? "image" : port == "depth" ? "depth" : port == "mask" ? "mask" : "",
        _ => ""
    };

    public bool has_output(string nodeKind, string port)
    {
        if (nodeKind == "Output") return false;
        if (nodeKind is "Alpha Extract" or "Mask") return port == "mask";
        if (nodeKind == "Depth Compare") return port is "image" or "mask";
        return PortType(nodeKind, port).Length > 0 && port is "image" or "output";
    }

    public bool has_input(string nodeKind, string port)
    {
        if (nodeKind is "Image Source" or "Solid Color" or "Layer Source") return false;
        if (nodeKind is "Alpha Extract" or "Blur") return port == "image";
        if (nodeKind == "Mask") return port is "image" or "mask";
        if (nodeKind == "Depth Compare") return port is "image" or "depth";
        return PortType(nodeKind, port).Length > 0 && port is not "output" and not "mask";
    }
}
