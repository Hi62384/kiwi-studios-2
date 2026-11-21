using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class CompositeWorkspaceToolbar : RefCounted
{
    private static T Widget<T>(Control workspace, string property) where T : GodotObject => (T)workspace.Get(property).AsGodotObject();
    public Settings build(Control workspace, HBoxContainer header, HBoxContainer tools)
    {
        Button Button(Node parent, string text, string method, string hint = "", params Variant[] arguments)
        {
            var button = new Button { Text = text, TooltipText = hint, CustomMinimumSize = new Vector2(0, 28) }; parent.AddChild(button);
            button.Pressed += () => workspace.Call(method, arguments); return button;
        }
        var document = workspace.Get("document").As<Resource>();
        var title = Widget<LineEdit>(workspace, "title_edit"); title.CustomMinimumSize = new Vector2(170, 0); title.PlaceholderText = "Composition name"; title.Text = document.Get("title").AsString(); header.AddChild(title); title.TextSubmitted += value => workspace.Call("_rename_document", value);
        Button(header, "Save", "save", "Save composition"); Button(header, "Save As", "save_as", "Save to a new project resource"); Button(header, "Undo", "undo"); Button(header, "Redo", "redo");
        Button(header, "Layers", "_set_mode", "", 0); Button(header, "Nodes", "_set_mode", "", 1); Button(header, "▶", "_toggle_play", "Play/pause composition preview"); Button(header, "Export Video", "_choose_export_video", "Render the composition to an MP4 video file");
        var time = Widget<SpinBox>(workspace, "time_spin"); time.MinValue = 0; time.MaxValue = document.Get("duration").AsDouble(); time.Step = 1 / document.Get("frame_rate").AsDouble(); time.Suffix = " s"; time.CustomMinimumSize = new Vector2(105, 0); header.AddChild(time); time.ValueChanged += value => workspace.Call("_time_changed", value);
        var resolution = Widget<Label>(workspace, "resolution_label"); resolution.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; resolution.HorizontalAlignment = HorizontalAlignment.Right; header.AddChild(resolution);
        var layers = new Godot.Collections.Array<Control>(); var graphs = new Godot.Collections.Array<Control>(); var nodes = new Godot.Collections.Array<Button>();
        void Layer(string text, string method, string hint = "", params Variant[] args) => layers.Add(Button(tools, text, method, hint, args));
        Layer("＋ Image", "choose_image", "Add a non-destructive image layer"); Layer("＋ Video", "choose_video", "Add a seekable video-footage layer");
        Layer("＋ Text", "_add_layer", "Add an editable text overlay", 5); Layer("＋ Shape", "_add_layer", "Add a vector-like procedural shape", 6);
        Layer("＋ Solid", "_add_layer", "Add a solid color layer", 1); Layer("＋ Adjustment", "_add_layer", "Add an adjustment layer", 8);
        Layer("Group", "_group_layers", "Group selected layers"); Layer("Ungroup", "_ungroup_layer", "Ungroup the selected group"); Layer("Duplicate", "_duplicate_layer", "Duplicate selected layer");
        Layer("Copy", "_copy_layer", "Copy selected layer"); Layer("Paste", "_paste_layer", "Paste copied layer"); Layer("↑", "_move_layer", "Move layer up", 1); Layer("↓", "_move_layer", "Move layer down", -1);
        Layer("Solo", "_toggle_solo", "Solo the selected layer"); Layer("Layer Graph", "_open_layer_graph", "Open or create a node graph that processes this layer"); Layer("Delete", "_delete_layer", "Remove selected layer"); Layer("Refresh", "_render", "Render the current composition");
        var search = Widget<LineEdit>(workspace, "graph_search"); search.PlaceholderText = "Find graph nodes…"; search.CustomMinimumSize = new Vector2(145, 28); search.Visible = false; tools.AddChild(search); search.TextChanged += value => workspace.Call("_filter_graph_nodes", value);
        graphs.Add(Button(tools, "New Graph", "_new_graph", "Graph node workflow; connect compatible ports"));
        foreach (string kind in new[] { "Image Source", "Layer Source", "Solid Color", "Over", "Merge", "Mask", "Blur", "Chroma Key", "Luma Key", "Color Grade", "Output" })
        { var button = Button(tools, kind, "_add_graph_node", "Graph node workflow; connect compatible ports", kind); graphs.Add(button); nodes.Add(button); }
        graphs.Add(Button(tools, "Duplicate Node", "_duplicate_graph_node", "Graph node workflow; connect compatible ports")); graphs.Add(Button(tools, "Delete Node", "_delete_graph_node", "Graph node workflow; connect compatible ports"));
        Button(header, "PNG Sequence", "choose_sequence_export", "Export color-managed RGBA frames", "png"); Button(header, "EXR Sequence", "choose_sequence_export", "Export scene-linear float RGBA frames", "exr");
        FileDialog FilePicker(FileDialog.FileModeEnum mode, FileDialog.AccessEnum access, string filter, string description, string callback)
        {
            var dialog = new FileDialog { FileMode = mode, Access = access }; dialog.AddFilter(filter, description); workspace.AddChild(dialog); dialog.FileSelected += value => workspace.Call(callback, value); return dialog;
        }
        var images = FilePicker(FileDialog.FileModeEnum.OpenFile, FileDialog.AccessEnum.Resources, "*.png, *.jpg, *.jpeg, *.webp, *.tga, *.bmp", "Images", "_image_selected");
        var videos = FilePicker(FileDialog.FileModeEnum.OpenFile, FileDialog.AccessEnum.Resources, "*.mp4, *.mov, *.mkv, *.webm, *.avi, *.m4v, *.ogv, *.mpeg, *.mpg", "Video footage", "_video_selected");
        var export = FilePicker(FileDialog.FileModeEnum.SaveFile, FileDialog.AccessEnum.Filesystem, "*.mp4", "MP4 video", "export_video");
        var timer = Widget<Timer>(workspace, "play_timer"); timer.WaitTime = 1 / document.Get("frame_rate").AsDouble(); timer.Timeout += () => workspace.Call("_advance_time"); workspace.AddChild(timer);
        return new Settings { ["layers"] = layers, ["graphs"] = graphs, ["nodes"] = nodes, ["images"] = images, ["videos"] = videos, ["export"] = export };
    }
}
