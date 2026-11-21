using Godot;
using System;
using System.Collections.Generic;

public partial class CompositeGraph : Resource
{
    [Export] public string id { get; set; } = Guid.NewGuid().ToString("N");
    [Export] public string name { get; set; } = "Main Graph";
    [Export] public Godot.Collections.Array<Resource> nodes { get; set; } = new();
    [Export] public Godot.Collections.Array<Resource> connections { get; set; } = new();
    [Export] public string output_node { get; set; } = "";

    public Resource? node(string id) => node_resource(this, id);
    public string[] validate() => validate_resource(this);
    public string[] compile_errors() => compile_errors_resource(this);
    private static string Text(Resource item, string property) => item.Get(property).AsString();

    public Resource? node_resource(Resource graph, string nodeId)
    {
        foreach (Variant value in graph.Get("nodes").AsGodotArray())
        {
            var item = value.As<Resource>();
            if (item != null && Text(item, "id") == nodeId) return item;
        }
        return null;
    }

    public string[] validate_resource(Resource graph)
    {
        var errors = new List<string>(); var ids = new HashSet<string>();
        var graphNodes = graph.Get("nodes").AsGodotArray();
        var graphEdges = graph.Get("connections").AsGodotArray();
        foreach (Variant value in graphNodes)
        {
            var item = value.As<Resource>();
            if (item == null || Text(item, "id").Length == 0 || !ids.Add(Text(item, "id"))) errors.Add("Graph node IDs must be present and unique.");
        }
        var adjacency = new Dictionary<string, List<string>>();
        var occupiedInputs = new HashSet<(string, string)>();
        using var ports = new CompositeGraphNode();
        foreach (Variant value in graphEdges)
        {
            var edge = value.As<Resource>();
            if (edge == null) { errors.Add("A graph connection refers to a missing node."); continue; }
            string from = Text(edge, "from_node"), to = Text(edge, "to_node");
            var source = node_resource(graph, from); var destination = node_resource(graph, to);
            if (source == null || destination == null) { errors.Add("A graph connection refers to a missing node."); continue; }
            string fromPort = Text(edge, "from_port"), toPort = Text(edge, "to_port");
            StringName sourceType = ports.port_type(Text(source, "kind"), fromPort), destinationType = ports.port_type(Text(destination, "kind"), toPort);
            if (!ports.has_output(Text(source, "kind"), fromPort) || !ports.has_input(Text(destination, "kind"), toPort)
                || sourceType.IsEmpty || destinationType.IsEmpty || sourceType != destinationType)
            { errors.Add("A graph connection has incompatible port types."); continue; }
            if (!occupiedInputs.Add((to, toPort))) errors.Add("An input port can only have one connection.");
            if (!adjacency.TryGetValue(from, out var next)) adjacency[from] = next = new List<string>();
            next.Add(to);
        }
        var visiting = new HashSet<string>(); var visited = new HashSet<string>();
        bool Cycle(string current)
        {
            if (visiting.Contains(current)) return true;
            if (visited.Contains(current)) return false;
            visiting.Add(current);
            if (adjacency.TryGetValue(current, out var next)) foreach (string child in next) if (Cycle(child)) return true;
            visiting.Remove(current); visited.Add(current); return false;
        }
        foreach (string nodeId in ids) if (Cycle(nodeId)) { errors.Add("Ordinary graph cycles are not supported."); break; }
        string output = Text(graph, "output_node");
        var outputResource = node_resource(graph, output);
        if (output.Length > 0 && (outputResource == null || Text(outputResource, "kind") != "Output")) errors.Add("Choose a valid Output node.");
        return errors.ToArray();
    }

    public string[] compile_errors_resource(Resource graph)
    {
        var errors = new List<string>(validate_resource(graph));
        if (Text(graph, "output_node").Length == 0) errors.Add("The graph has no Output node.");
        var edges = graph.Get("connections").AsGodotArray();
        foreach (Variant value in graph.Get("nodes").AsGodotArray())
        {
            var item = value.As<Resource>(); if (item == null) continue;
            string kind = Text(item, "kind"), nodeId = Text(item, "id");
            foreach (string port in Required(kind))
            {
                bool connected = false;
                foreach (Variant edgeValue in edges)
                {
                    var edge = edgeValue.As<Resource>();
                    if (edge != null && Text(edge, "to_node") == nodeId && Text(edge, "to_port") == port) { connected = true; break; }
                }
                if (!connected) errors.Add($"Node '{kind}' is missing its '{port}' input.");
            }
        }
        return errors.ToArray();
    }

    private static string[] Required(string kind) => kind switch
    {
        "Over" or "Merge" => new[] { "foreground", "background" },
        "Color Grade" or "Alpha Extract" or "Blur" or "Chroma Key" or "Luma Key" or "Output" => new[] { "image" },
        "Mask" => new[] { "image", "mask" }, "Depth Compare" => new[] { "image", "depth" }, _ => Array.Empty<string>()
    };
}
