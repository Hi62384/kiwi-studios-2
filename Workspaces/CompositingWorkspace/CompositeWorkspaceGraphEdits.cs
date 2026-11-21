using Godot;
using Settings = Godot.Collections.Dictionary;

/// <summary>Document graph mutations, shared by the workspace and migration tests.</summary>
public partial class CompositeWorkspaceGraphEdits : RefCounted
{
    private readonly CompositeGraph _rules = new();
    private static string Text(Resource resource, string property) => resource.Get(property).AsString();
    private static Settings Result(bool changed, string selected, string message) => new()
    { ["changed"] = changed, ["selected_id"] = selected, ["message"] = message };

    public Resource? find_graph(Resource document, string id)
    {
        foreach (Variant value in document.Get("graphs").AsGodotArray())
        { var graph = value.As<Resource>(); if (graph != null && Text(graph, "id") == id) return graph; }
        return null;
    }

    public Resource create_graph(Resource document, string layerId)
    {
        using var documents = new CompositingDocument();
        var layer = documents.layer_resource(document, layerId);
        if (layer != null)
        {
            var existing = find_graph(document, Text(layer, "processing_graph_id"));
            if (existing != null) { document.Set("active_graph_id", Text(existing, "id")); return existing; }
        }
        else if (document.Get("graphs").AsGodotArray().Count > 0)
        {
            var first = document.Get("graphs").AsGodotArray()[0].As<Resource>();
            document.Set("active_graph_id", Text(first, "id")); return first;
        }
        var graph = new CompositeGraph(); var output = new CompositeGraphNode { kind = "Output", position = new Vector2(420, 120) };
        graph.nodes.Add(output); graph.output_node = output.id;
        if (layer != null)
        {
            graph.name = Text(layer, "name") + " Processing";
            var source = new CompositeGraphNode { kind = "Layer Source", position = new Vector2(80, 120), settings = new Settings { ["layer_id"] = layerId } };
            graph.nodes.Insert(0, source);
            graph.connections.Add(new CompositeGraphConnection { from_node = source.id, from_port = "image", to_node = output.id, to_port = "image" });
            layer.Set("processing_graph_id", graph.id);
        }
        var graphs = document.Get("graphs").AsGodotArray(); graphs.Add(graph); document.Set("graphs", graphs); document.Set("active_graph_id", graph.id); return graph;
    }

    public Settings add_node(Resource graph, string kind, string layerId)
    {
        var nodes = graph.Get("nodes").AsGodotArray();
        var node = new CompositeGraphNode { kind = kind, position = new Vector2(80 + nodes.Count * 35, 80 + nodes.Count * 35) };
        node.settings = kind switch
        {
            "Solid Color" => new Settings { ["color"] = Colors.White },
            "Image Source" => new Settings { ["path"] = "" },
            "Layer Source" => new Settings { ["layer_id"] = layerId },
            "Merge" => new Settings { ["mode"] = 0, ["opacity"] = 1.0 },
            "Blur" => new Settings { ["radius"] = 2 },
            _ => new Settings()
        };
        nodes.Add(node); graph.Set("nodes", nodes); if (kind == "Output") graph.Set("output_node", node.id);
        return Result(true, node.id, "Add " + kind + " node");
    }

    public Settings duplicate_node(Resource graph, string id)
    {
        var node = _rules.node_resource(graph, id); if (node == null) return Result(false, id, "");
        var copy = (Resource)node.Duplicate(true); copy.Set("id", System.Guid.NewGuid().ToString("N")); copy.Set("position", node.Get("position").AsVector2() + new Vector2(40, 40));
        var nodes = graph.Get("nodes").AsGodotArray(); nodes.Add(copy); graph.Set("nodes", nodes); return Result(true, Text(copy, "id"), "Duplicate graph node");
    }

    public Settings delete_node(Resource graph, string id)
    {
        var node = _rules.node_resource(graph, id); if (node == null) return Result(false, id, "");
        var edges = graph.Get("connections").AsGodotArray();
        for (int i = edges.Count - 1; i >= 0; i--) { var edge = edges[i].As<Resource>(); if (Text(edge, "from_node") == id || Text(edge, "to_node") == id) edges.RemoveAt(i); }
        graph.Set("connections", edges); var nodes = graph.Get("nodes").AsGodotArray(); nodes.Remove(node); graph.Set("nodes", nodes);
        if (Text(graph, "output_node") == id) graph.Set("output_node", "");
        // Keep the layer bound to its graph while the user edits it, including incomplete graphs.
        return Result(true, "", "Delete graph node");
    }

    public Settings connect_nodes(Resource graph, string from, string fromPort, string to, string toPort)
    {
        var edge = new CompositeGraphConnection { from_node = from, from_port = fromPort, to_node = to, to_port = toPort };
        var edges = graph.Get("connections").AsGodotArray(); edges.Add(edge); graph.Set("connections", edges);
        var errors = _rules.validate_resource(graph);
        if (errors.Length > 0)
        { edges.Remove(edge); graph.Set("connections", edges); return Result(false, "", errors[0]); }
        return Result(true, "", "Connect compositing nodes");
    }

    public Settings disconnect_nodes(Resource graph, string from, string fromPort, string to, string toPort)
    {
        var edges = graph.Get("connections").AsGodotArray(); bool changed = false;
        for (int i = edges.Count - 1; i >= 0; i--)
        {
            var edge = edges[i].As<Resource>();
            if (Text(edge, "from_node") != from || Text(edge, "from_port") != fromPort || Text(edge, "to_node") != to || Text(edge, "to_port") != toPort) continue;
            edges.RemoveAt(i); changed = true;
        }
        graph.Set("connections", edges); return Result(changed, "", "Disconnect compositing nodes");
    }
}
