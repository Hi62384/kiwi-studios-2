using Godot;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class CompositeGraphView : RefCounted
{
    public string[] inputs(string kind) => kind switch
    {
        "Over" or "Merge" => new[] { "foreground", "background" },
        "Color Grade" or "Alpha Extract" or "Blur" or "Output" or "Chroma Key" or "Luma Key" => new[] { "image" },
        "Mask" => new[] { "image", "mask" },
        "Depth Compare" => new[] { "image", "depth" },
        _ => System.Array.Empty<string>()
    };
    public string[] outputs(string kind) => kind switch
    {
        "Image Source" or "Layer Source" or "Solid Color" or "Over" or "Merge" or "Mask" or "Blur" => new[] { "image" },
        "Chroma Key" or "Luma Key" or "Color Grade" => new[] { "output" },
        "Alpha Extract" => new[] { "mask" },
        "Depth Compare" => new[] { "image", "mask" },
        _ => System.Array.Empty<string>()
    };
    public int port_type(string port) => port == "mask" ? 1 : port == "depth" ? 2 : 0;
    private static string Text(Resource value, string property) => value.Get(property).AsString();

    public void refresh(GraphEdit view, Resource? graph, string selected)
    {
        if (!view.IsInsideTree() || !view.IsNodeReady()) return;
        view.ClearConnections();
        foreach (Node child in view.GetChildren())
            if (child is GraphNode) { view.RemoveChild(child); child.QueueFree(); }
        if (graph == null) return;
        var visualById = new Dictionary<string, GraphNode>(); int index = 0;
        foreach (Variant value in graph.Get("nodes").AsGodotArray())
        {
            var model = value.As<Resource>(); if (model == null) continue;
            string id = Text(model, "id"), kind = Text(model, "kind");
            var visual = new GraphNode { Name = "CompositeNode" + index++, Title = kind, PositionOffset = model.Get("position").AsVector2() };
            visual.SetMeta("composite_id", id); view.AddChild(visual); visualById[id] = visual;
            string[] ins = inputs(kind), outs = outputs(kind); var inputIndices = new Settings(); var outputIndices = new Settings();
            int rows = System.Math.Max(1, System.Math.Max(ins.Length, outs.Length));
            for (int rowIndex = 0; rowIndex < rows; rowIndex++)
            {
                bool hasInput = rowIndex < ins.Length, hasOutput = rowIndex < outs.Length;
                var row = new HBoxContainer(); visual.AddChild(row);
                var left = new Label { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
                var right = new Label { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, HorizontalAlignment = HorizontalAlignment.Right };
                if (hasInput) { left.Text = ins[rowIndex]; inputIndices[ins[rowIndex]] = rowIndex; }
                if (hasOutput) { right.Text = outs[rowIndex]; outputIndices[outs[rowIndex]] = rowIndex; }
                row.AddChild(left); row.AddChild(right);
                visual.SetSlot(rowIndex, hasInput, port_type(hasInput ? ins[rowIndex] : ""), new Color("74d9c4"), hasOutput, port_type(hasOutput ? outs[rowIndex] : ""), new Color("74d9c4"));
            }
            visual.SetMeta("input_ports", inputIndices); visual.SetMeta("output_ports", outputIndices); visual.Selected = id == selected;
        }
        foreach (Variant value in graph.Get("connections").AsGodotArray())
        {
            var edge = value.As<Resource>(); if (edge == null) continue;
            if (!visualById.TryGetValue(Text(edge, "from_node"), out var from) || !visualById.TryGetValue(Text(edge, "to_node"), out var to)) continue;
            var fromPorts = from.GetMeta("output_ports").AsGodotDictionary(); var toPorts = to.GetMeta("input_ports").AsGodotDictionary();
            if (fromPorts.TryGetValue(Text(edge, "from_port"), out var fromPort) && toPorts.TryGetValue(Text(edge, "to_port"), out var toPort)) view.ConnectNode(from.Name, fromPort.AsInt32(), to.Name, toPort.AsInt32());
        }
    }

    public bool capture_positions(GraphEdit view, Resource graph)
    {
        bool changed = false; using var rules = new CompositeGraph();
        foreach (Node child in view.GetChildren())
        {
            if (child is not GraphNode visual) continue;
            var model = rules.node_resource(graph, visual.GetMeta("composite_id", "").AsString());
            if (model == null || model.Get("position").AsVector2() == visual.PositionOffset) continue;
            model.Set("position", visual.PositionOffset); changed = true;
        }
        return changed;
    }
}
