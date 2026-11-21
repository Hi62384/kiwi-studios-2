using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class CompositingWorkspace : Control
{
    [Signal] public delegate void document_changedEventHandler();
    [Signal] public delegate void composition_savedEventHandler(string path, Resource document);
    [Signal] public delegate void export_rejectedEventHandler(bool success);
    public Resource document { get; set; } = new CompositingDocument();
    public CompositingEvaluator evaluator { get; set; } = new();
    public Variant source { get; set; }
    public string path { get; set; } = "";
    public string selected_id { get; set; } = "";
    public string selected_graph_node_id { get; set; } = "";
    public bool dirty { get; set; }
    public int mode { get; set; }
    public double preview_time { get; set; }
    public TextureRect image_view { get; set; } = new();
    public Tree layer_tree { get; set; } = new();
    public VBoxContainer inspector { get; set; } = new();
    public Label status { get; set; } = new();
    public LineEdit title_edit { get; set; } = new();
    public Label resolution_label { get; set; } = new();
    public GraphEdit graph_edit { get; set; } = new();
    public HSlider time_slider { get; set; } = new();
    public SpinBox time_spin { get; set; } = new();
    public Timer play_timer { get; set; } = new();
    public LineEdit graph_search { get; set; } = new();
    public Resource? _graph_move_before { get; set; }
    public Godot.Collections.Array<Control> _layer_controls { get; set; } = new();
    public Godot.Collections.Array<Control> _graph_controls { get; set; } = new();
    public Godot.Collections.Array<Button> _graph_node_controls { get; set; } = new();
    public CompositeWorkspaceExporter media_exporter { get; set; } = new();
    private FileDialog _images = null!, _videos = null!, _export = null!;
    private bool _refreshing;
    private double _videoRetry;
    private readonly CompositingDocument _documents = new();
    private readonly CompositeWorkspaceEdits _edits = new();
    private readonly CompositeWorkspaceHistory _history = new();
    private readonly CompositeWorkspacePreview _preview = new();
    private readonly CompositeWorkspaceGraphEdits _graphs = new();
    private readonly CompositeGraphView _graphView = new();
    private readonly CompositeWorkspaceFiles _files = new();
    private readonly CompositeWorkspacePlayback _playback = new();
    private readonly CompositeLayerTree _tree = new();
    private readonly CompositeWorkspaceAnimation _animation = new();
    private readonly CompositeLayerInspector _layerInspector = new();
    private readonly CompositeGraphInspector _graphInspector = new();
    private static string Text(Resource resource, string property) => resource.Get(property).AsString();
    private Resource Snapshot() => (Resource)document.Duplicate(true);
    private Resource? Layer(string id) => _documents.layer_resource(document, id);
    private static string FileName(string value)
    { string result = value.Trim(); foreach (char invalid in ":/\\?*\"|%<>") result = result.Replace(invalid, '_'); return result; }

    public override void _Ready()
    {
        AddChild(media_exporter); media_exporter.progress += message => status.Text = message;
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        using var layout = new CompositeWorkspaceLayout(); using var toolbar = new CompositeWorkspaceToolbar();
        var structure = layout.build(this); var controls = toolbar.build(this, structure["header"].As<HBoxContainer>(), structure["tools"].As<HBoxContainer>());
        _layer_controls = controls["layers"].AsGodotArray<Control>(); _graph_controls = controls["graphs"].AsGodotArray<Control>(); _graph_node_controls = controls["nodes"].AsGodotArray<Button>();
        _images = controls["images"].As<FileDialog>(); _videos = controls["videos"].As<FileDialog>(); _export = controls["export"].As<FileDialog>();
        document = _files.ensure_document(document); _set_mode(0);
    }
    public override void _Process(double delta)
    {
        if (!status.Text.StartsWith("Waiting for the requested video frame:", StringComparison.Ordinal)) return;
        _videoRetry += delta; if (_videoRetry >= .15) { _videoRetry = 0; _render(); }
    }
    public void _rename_document(string value)
    { var before = Snapshot(); document.Set("title", string.IsNullOrWhiteSpace(value) ? "Untitled Composition" : value.Trim()); _commit("Rename composition", before); }
    public void open_document(Variant value, Settings state)
    {
        var opened = _files.open_source(value); document = opened["document"].As<Resource>(); path = opened["path"].AsString(); source = opened["source"]; dirty = opened["dirty"].AsBool();
        if (state.TryGetValue("selected_id", out var selected)) selected_id = selected.AsString();
        if (state.TryGetValue("mode", out var selectedMode)) mode = selectedMode.AsInt32();
        if (state.TryGetValue("preview_time", out var time)) preview_time = time.AsDouble();
        _history.clear(); evaluator.clear_cache(); document = _files.ensure_document(document); _refresh_ui(); _set_mode(mode);
        if (opened["failed"].AsBool()) status.Text = "The composition could not be read; opened an unsaved blank document.";
    }
    public void open_source(Variant value, Settings state) => open_document(value, state);
    public Signal export_video(string destination) => Export(destination, "mp4");
    public Signal export_sequence(string destination, string format) => Export(destination, format);
    private Signal Export(string destination, string format)
    {
        if (start_media_export(destination, format)) return new Signal(media_exporter, CompositeWorkspaceExporter.SignalName.completed);
        Callable.From(() => EmitSignal(SignalName.export_rejected, false)).CallDeferred();
        return new Signal(this, SignalName.export_rejected);
    }
    public Settings capture_state() => new() { ["document"] = document, ["path"] = path, ["selected_id"] = selected_id, ["mode"] = mode, ["dirty"] = dirty, ["preview_time"] = preview_time };
    public void _set_mode(int value)
    {
        mode = value; ((Control)image_view.GetParent().GetParent()).Visible = true; graph_edit.Visible = value == 1; graph_search.Visible = value == 1;
        foreach (var control in _layer_controls) control.Visible = value == 0; foreach (var control in _graph_controls) control.Visible = value == 1;
        _filter_graph_nodes(graph_search.Text); _refresh_graph(); _refresh_inspector(); _render();
    }
    public void _filter_graph_nodes(string query)
    { string normalized = query.Trim(); foreach (var button in _graph_node_controls) button.Visible = mode == 1 && (normalized.Length == 0 || button.Text.Contains(normalized, StringComparison.OrdinalIgnoreCase)); }
    public void _refresh_ui()
    {
        _refreshing = true; title_edit.Text = Text(document, "title"); var size = document.Get("canvas_size").AsVector2I();
        resolution_label.Text = size.X + " × " + size.Y + "  ·  " + document.Get("frame_rate").AsDouble().ToString("F2", System.Globalization.CultureInfo.InvariantCulture) + " fps";
        _playback.configure(document, play_timer, time_spin, time_slider, preview_time); _tree.refresh(layer_tree, document, selected_id);
        _refresh_inspector(); _refresh_graph(); _refreshing = false;
    }
    public void _layer_selected()
    { if (_refreshing) return; var item = layer_tree.GetSelected(); if (item == null) return; selected_id = item.GetMetadata(0).AsString(); _refresh_inspector(); _render(); }
    public void _refresh_inspector()
    {
        foreach (Node child in inspector.GetChildren()) { inspector.RemoveChild(child); child.QueueFree(); }
        if (mode == 1 && selected_graph_node_id.Length > 0)
        { if (!_graphInspector.build(inspector, document, _graph_by_id(Text(document, "active_graph_id")), selected_graph_node_id, this)) selected_graph_node_id = ""; }
        else _layerInspector.build(inspector, document, Layer(selected_id), preview_time, this);
    }
    public void _set_graph_setting(Resource node, string key, Variant value)
    { var before = Snapshot(); var settings = node.Get("settings").AsGodotDictionary(); settings[key] = value; node.Set("settings", settings); _commit("Change " + Text(node, "kind") + " settings", before); }
    public void _set_layer_property(string label, string property, Variant value)
    { var target = Layer(selected_id); if (target == null) return; var before = Snapshot(); target.Set(property, value); _commit(label, before); }
    public void _set_animated_property(string property, Variant value)
    { var before = Snapshot(); if (_animation.set_property(document, selected_id, property, preview_time, value)) _commit("Change " + property, before); }
    public void _key_layer_transform(Resource layer)
    { var before = Snapshot(); if (_animation.key_transform(document, Text(layer, "id"), preview_time)) _commit("Set transform and opacity keys", before); }
    public void _commit(string label, Resource before) { if (_history.commit(document, before)) _changed(label); }
    private void ApplyEdit(Settings result, Resource before)
    {
        if (result["changed"].AsBool()) { selected_id = result["selected_id"].AsString(); _commit(result["message"].AsString(), before); }
        else if (result["message"].AsString().Length > 0) status.Text = result["message"].AsString();
    }
    public void _changed(string message)
    { dirty = true; evaluator.clear_cache(); status.Text = message; _refresh_ui(); _render(); EmitSignal(SignalName.document_changed); }
    public void _add_layer(int kind)
    {
        string[] names = { "Image", "Solid Color", "Video", "CGI", "VFX", "Text", "Shape", "Mask", "Adjustment", "Group", "Linked Composition" };
        if (kind < 0 || kind >= names.Length) return;
        var before = Snapshot(); var layer = _documents.add_layer_resource(document, kind, names[kind]); selected_id = Text(layer, "id");
        if (kind == 1) layer.Set("color", new Color(.2f, .24f, .3f));
        else if (kind == 8) layer.Set("settings", new Settings { ["exposure"] = 0.0, ["brightness"] = 0.0, ["contrast"] = 1.0, ["saturation"] = 1.0 });
        else if (kind == 6) { layer.Set("settings", new Settings { ["shape"] = "rectangle", ["size"] = new Vector2I(256, 256) }); layer.Set("color", Colors.White); }
        else if (kind == 5) { layer.Set("settings", new Settings { ["text"] = "Text", ["font_size"] = 72, ["size"] = new Vector2I(640, 180) }); layer.Set("color", Colors.White); }
        _commit("Add layer", before);
    }
    public void _delete_layer() { var before = Snapshot(); ApplyEdit(_edits.delete_layer(document, selected_id), before); }
    public void _duplicate_layer() { var before = Snapshot(); ApplyEdit(_edits.duplicate_layer(document, selected_id), before); }
    public void _move_layer(int direction) { var before = Snapshot(); ApplyEdit(_edits.move_layer(document, selected_id, direction), before); }
    public Godot.Collections.Array<string> _selected_layer_ids() => _tree.selected_layers(layer_tree, document, selected_id);
    public void _group_layers() { var before = Snapshot(); ApplyEdit(_edits.group_layers(document, _selected_layer_ids()), before); }
    public void _ungroup_layer() { var before = Snapshot(); ApplyEdit(_edits.ungroup_layer(document, selected_id), before); }
    public void _copy_layer() { var result = _edits.copy_layer(document, selected_id); if (result["message"].AsString().Length > 0) status.Text = result["message"].AsString(); }
    public void _paste_layer() { var before = Snapshot(); ApplyEdit(_edits.paste_layer(document), before); }
    public string _clone_graph(Resource graph, string newLayerId) => _edits.clone_graph(document, graph, new Settings());
    public string _clone_processing_graph(string id, string newLayerId) { var graph = _graph_by_id(id); return graph == null ? "" : _clone_graph(graph, newLayerId); }
    public void _toggle_solo() { var before = Snapshot(); document.Set("solo_layer_id", Text(document, "solo_layer_id") == selected_id ? "" : selected_id); _commit("Solo layer", before); }
    public void choose_image() => _images.PopupCentered(new Vector2I(640, 440));
    public void choose_video() => _videos.PopupCentered(new Vector2I(680, 460));
    public void _image_selected(string sourcePath)
    { var before = Snapshot(); var layer = _documents.add_layer_resource(document, 0, System.IO.Path.GetFileNameWithoutExtension(sourcePath)); layer.Set("source_path", sourcePath); selected_id = Text(layer, "id"); _commit("Add image layer", before); }
    public void _video_selected(string sourcePath)
    {
        var metadata = GD.Load<CSharpScript>("res://scripts/actors/core/ActorVideo.cs").Call("info", sourcePath).AsGodotDictionary();
        if (metadata.Count == 0) { status.Text = "The video could not be opened. Check the format and FFmpeg setup."; return; }
        var before = Snapshot(); var layer = _documents.add_layer_resource(document, 2, System.IO.Path.GetFileNameWithoutExtension(sourcePath)); layer.Set("source_path", sourcePath);
        layer.Set("end_time", Math.Min(metadata["duration"].AsDouble(), document.Get("duration").AsDouble())); selected_id = Text(layer, "id"); _commit("Add video footage layer", before);
    }
    public void _choose_export_video() { _export.CurrentFile = FileName(Text(document, "title")) + ".mp4"; _export.PopupCentered(new Vector2I(740, 480)); }
    public bool start_media_export(string destination, string format)
    {
        string encoder = format == "mp4" ? GD.Load<CSharpScript>("res://scripts/actors/core/ActorVideo.cs").Call("executable", "ffmpeg").AsString() : "";
        if (media_exporter.start_export(document, destination, format, encoder)) return true;
        status.Text = "An export is already running."; return false;
    }
    public void choose_sequence_export(string format)
    { var dialog = _files.sequence_dialog(this, format); dialog.DirSelected += folder => { Call("export_sequence", folder, format); dialog.QueueFree(); }; dialog.PopupCentered(new Vector2I(740, 480)); }
    public void _render()
    {
        _videoRetry = 0; var preview = _preview.prepare(document, 1024); var result = evaluator.evaluate(preview, preview_time, false);
        if (mode == 1)
        {
            var graph = _graphs.find_graph(preview, Text(preview, "active_graph_id"));
            if (graph != null) result = selected_graph_node_id.Length > 0 ? evaluator.evaluate_node_output(preview, graph, selected_graph_node_id, preview_time) : evaluator.evaluate_graph(preview, graph, preview_time, false);
        }
        if (result?.image == null) { status.Text = evaluator.last_error; return; }
        image_view.Texture = ImageTexture.CreateFromImage(_preview.display_preview(result.image)); status.Text = "Preview ready · " + evaluator.nodes_evaluated + " nodes";
    }
    public void _time_changed(double value) { preview_time = _playback.seek(document, time_spin, time_slider, value); evaluator.clear_cache(); RefreshTimeInspector(); _render(); }
    public void _toggle_play() => _playback.toggle(play_timer);
    public void _advance_time() { preview_time = _playback.advance(document, time_spin, time_slider, preview_time); RefreshTimeInspector(); _render(); }
    private void RefreshTimeInspector()
    { if (mode != 0 || Layer(selected_id) == null) return; foreach (string property in new[] { "position", "rotation", "scale", "opacity" }) if (_documents.has_layer_track_resource(document, selected_id, property)) { _refresh_inspector(); break; } }
    public Image _display_preview(Image image) => _preview.display_preview(image);
    public Resource? _graph_by_id(string id) => _graphs.find_graph(document, id);
    public void _refresh_graph()
    {
        if (!graph_edit.IsInsideTree()) return; if (!graph_edit.IsNodeReady()) { Callable.From(_refresh_graph).CallDeferred(); return; }
        var graph = _graph_by_id(Text(document, "active_graph_id")); if (graph == null && document.Get("graphs").AsGodotArray().Count > 0) graph = document.Get("graphs").AsGodotArray()[0].As<Resource>();
        _graphView.refresh(graph_edit, graph, selected_graph_node_id);
    }
    public void _new_graph() { var before = Snapshot(); _graphs.create_graph(document, ""); mode = 1; _commit("Create node graph", before); _set_mode(1); }
    public void _open_layer_graph() { if (Layer(selected_id) == null) { status.Text = "Select a layer first."; return; } var before = Snapshot(); _graphs.create_graph(document, selected_id); mode = 1; _commit("Create layer processing graph", before); _set_mode(1); }
    public void _graph_node_selected(Node node) { if (_refreshing) return; selected_graph_node_id = node.GetMeta("composite_id", "").AsString(); _refresh_inspector(); }
    public void _graph_node_deselected(Node node) { if (_refreshing || node.GetMeta("composite_id", "").AsString() != selected_graph_node_id) return; selected_graph_node_id = ""; _refresh_inspector(); }
    private void ApplyGraph(Settings result, Resource before, bool select = false)
    { if (result["changed"].AsBool()) { if (select) selected_graph_node_id = result["selected_id"].AsString(); _commit(result["message"].AsString(), before); } else if (result["message"].AsString().Length > 0) status.Text = result["message"].AsString(); }
    public void _duplicate_graph_node() { var graph = _graph_by_id(Text(document, "active_graph_id")); if (graph == null) return; var before = Snapshot(); ApplyGraph(_graphs.duplicate_node(graph, selected_graph_node_id), before, true); }
    public void _delete_graph_node() { var graph = _graph_by_id(Text(document, "active_graph_id")); if (graph == null) return; var before = Snapshot(); ApplyGraph(_graphs.delete_node(graph, selected_graph_node_id), before, true); }
    public void _add_graph_node(string kind) { var before = Snapshot(); var graph = _graph_by_id(Text(document, "active_graph_id")) ?? _graphs.create_graph(document, ""); ApplyGraph(_graphs.add_node(graph, kind, selected_id), before, true); }
    public string[] _graph_inputs(string kind) => _graphView.inputs(kind);
    public string[] _graph_outputs(string kind) => _graphView.outputs(kind);
    public int _port_type(string port) => _graphView.port_type(port);
    private void GraphConnection(StringName fromName, int fromPort, StringName toName, int toPort, bool connect)
    {
        var from = graph_edit.GetNodeOrNull<GraphNode>(new NodePath(fromName.ToString())); var to = graph_edit.GetNodeOrNull<GraphNode>(new NodePath(toName.ToString())); var graph = _graph_by_id(Text(document, "active_graph_id"));
        if (from == null || to == null || graph == null) return; string fromKey = "", toKey = "";
        foreach (var pair in from.GetMeta("output_ports").AsGodotDictionary()) if (pair.Value.AsInt32() == fromPort) fromKey = pair.Key.AsString();
        foreach (var pair in to.GetMeta("input_ports").AsGodotDictionary()) if (pair.Value.AsInt32() == toPort) toKey = pair.Key.AsString();
        if (fromKey.Length == 0 || toKey.Length == 0) return; var before = Snapshot(); string fromId = from.GetMeta("composite_id").AsString(), toId = to.GetMeta("composite_id").AsString();
        ApplyGraph(connect ? _graphs.connect_nodes(graph, fromId, fromKey, toId, toKey) : _graphs.disconnect_nodes(graph, fromId, fromKey, toId, toKey), before);
    }
    public void _graph_connect_request(StringName from, int fromPort, StringName to, int toPort) => GraphConnection(from, fromPort, to, toPort, true);
    public void _graph_disconnect_request(StringName from, int fromPort, StringName to, int toPort) => GraphConnection(from, fromPort, to, toPort, false);
    public void _graph_nodes_moved() { var graph = _graph_by_id(Text(document, "active_graph_id")); if (graph == null) return; if (_graphView.capture_positions(graph_edit, graph) && _graph_move_before != null) { var before = _graph_move_before; _graph_move_before = null; _commit("Move compositing nodes", before); } }
    public void save() { if (path.Length > 0) _save_path(path); else save_as(); }
    public void save_as() { var dialog = _files.save_dialog(this, FileName(Text(document, "title")) + ".tres"); dialog.FileSelected += destination => { _save_path(destination); dialog.QueueFree(); }; dialog.PopupCentered(new Vector2I(650, 440)); }
    public void _save_path(string destination)
    { var result = _files.save_document(document, destination); status.Text = result["message"].AsString(); if (!result["success"].AsBool()) return; path = destination; source = destination; dirty = false; EmitSignal(SignalName.composition_saved, destination, document); EmitSignal(SignalName.document_changed); }
    public void undo() { var restored = _history.undo(document); if (restored != null) { document = restored; _changed("Undo"); } }
    public void redo() { var restored = _history.redo(document); if (restored != null) { document = restored; _changed("Redo"); } }
}
