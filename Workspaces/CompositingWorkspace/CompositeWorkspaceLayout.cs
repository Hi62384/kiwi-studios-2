using Godot;
using Settings = Godot.Collections.Dictionary;

public partial class CompositeWorkspaceLayout : RefCounted
{
    private static T Widget<T>(Control workspace, string property) where T : GodotObject => (T)workspace.Get(property).AsGodotObject();
    public Settings build(Control workspace)
    {
        var root = new VBoxContainer(); root.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); root.AddThemeConstantOverride("separation", 6); workspace.AddChild(root);
        var header = new HBoxContainer(); root.AddChild(header);
        var toolsScroll = new ScrollContainer { CustomMinimumSize = new Vector2(0, 36), HorizontalScrollMode = ScrollContainer.ScrollMode.Auto, VerticalScrollMode = ScrollContainer.ScrollMode.Disabled }; root.AddChild(toolsScroll);
        var tools = new HBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; toolsScroll.AddChild(tools);
        var split = new HSplitContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill }; root.AddChild(split);
        var left = new VBoxContainer { CustomMinimumSize = new Vector2(210, 0) }; split.AddChild(left); left.AddChild(new Label { Text = "LAYERS · bottom to top" });
        var tree = Widget<Tree>(workspace, "layer_tree"); tree.SizeFlagsVertical = Control.SizeFlags.ExpandFill; tree.SelectMode = Tree.SelectModeEnum.Multi; left.AddChild(tree);
        tree.ItemSelected += () => workspace.Call("_layer_selected"); tree.MultiSelected += (_, _, selected) => { if (selected) workspace.Call("_layer_selected"); };
        var center = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; split.AddChild(center);
        var viewer = new ScrollContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, HorizontalScrollMode = ScrollContainer.ScrollMode.Auto, VerticalScrollMode = ScrollContainer.ScrollMode.Auto }; center.AddChild(viewer);
        var background = new CenterContainer { CustomMinimumSize = new Vector2(480, 270), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, SizeFlagsVertical = Control.SizeFlags.ExpandFill }; viewer.AddChild(background);
        var image = Widget<TextureRect>(workspace, "image_view"); image.ExpandMode = TextureRect.ExpandModeEnum.FitWidthProportional; image.StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered; image.CustomMinimumSize = new Vector2(480, 270); background.AddChild(image);
        var graph = Widget<GraphEdit>(workspace, "graph_edit"); graph.Visible = false; graph.SizeFlagsVertical = Control.SizeFlags.ExpandFill; graph.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; graph.ShowGrid = true;
        graph.Connect(GraphEdit.SignalName.ConnectionRequest, new Callable(workspace, "_graph_connect_request")); graph.Connect(GraphEdit.SignalName.DisconnectionRequest, new Callable(workspace, "_graph_disconnect_request"));
        graph.Connect(GraphEdit.SignalName.NodeSelected, new Callable(workspace, "_graph_node_selected")); graph.Connect(GraphEdit.SignalName.NodeDeselected, new Callable(workspace, "_graph_node_deselected"));
        graph.BeginNodeMove += () => workspace.Set("_graph_move_before", workspace.Get("document").As<Resource>().Duplicate(true)); graph.EndNodeMove += () => workspace.Call("_graph_nodes_moved"); center.AddChild(graph);
        var slider = Widget<HSlider>(workspace, "time_slider"); slider.MinValue = 0; center.AddChild(slider); slider.ValueChanged += value => workspace.Call("_time_changed", value);
        var inspectorScroll = new ScrollContainer { CustomMinimumSize = new Vector2(250, 0) }; split.AddChild(inspectorScroll); inspectorScroll.AddChild(Widget<VBoxContainer>(workspace, "inspector"));
        var status = Widget<Label>(workspace, "status"); status.Text = "Ready"; root.AddChild(status);
        return new Settings { ["header"] = header, ["tools"] = tools };
    }
}
