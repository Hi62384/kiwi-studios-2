using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations : RefCounted
{
    private static Signal FileJob(Control workspace, string mode, string destination = "")
    { var job = new ModelWorkspaceFileJob(); workspace.AddChild(job); job.start(workspace, mode, destination); return new Signal(job, ModelWorkspaceFileJob.SignalName.completed); }
    public Signal open_dialog(Control workspace) => FileJob(workspace, "open");
    public Signal load_material(Control workspace) => FileJob(workspace, "material");
    public Signal save(Control workspace) => FileJob(workspace, "save");
    public Signal save_as(Control workspace) => FileJob(workspace, "save_as");
    public Signal save_to(Control workspace, string destination) => FileJob(workspace, "save_to", destination);
    public Signal to_scene_after_save(Control workspace) => FileJob(workspace, "scene");
    public Signal boolean(Control workspace, string command)
    { var job = new ModelWorkspaceBooleanJob(); workspace.AddChild(job); job.start(workspace, command); return new Signal(job, ModelWorkspaceBooleanJob.SignalName.completed); }
    private readonly ModelSelection _selection = new();
    private readonly ModelGeometryOperations _geometry = new();
    private readonly ModelComponentOperations _components = new();
    private readonly ModelMeshOperations _meshes = new();
    private static RefCounted Session(Control workspace) => workspace.Get("session").As<RefCounted>();
    private static void Status(Control workspace, string text) => workspace.Get("status").As<Label>().Text = text;
    private static void Action(RefCounted session, string label, Action operation) { session.Call("begin"); try { operation(); session.Call("commit", label); } catch { session.Call("cancel"); throw; } }
    public void selection(Control workspace, string command)
    {
        var session = Session(workspace); string mode = session.Get("mode").AsString(); var item = session.Call("primary").As<Resource>();
        if (mode == "Object")
        {
            if (command != "Select all" && command != "Invert selection") { Status(workspace, "Switch to vertex, edge, or face selection (2–4) first."); return; }
            var selected = session.Get("selected").AsGodotArray<string>(); var old = new HashSet<string>(selected); selected.Clear(); var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
            foreach (var other in lookup.Values) { string id = other.Get("id").AsString(); if (ModelDocumentOperations.Accessible(lookup, other, false) && !other.Get("locked").AsBool() && (command != "Invert selection" || !old.Contains(id))) selected.Add(id); }
        }
        else if (item?.Get("mesh").As<Resource>() is Resource mesh)
        {
            var data = new ModelMeshOperations.Snapshot(mesh); int count = mode == "Vertex" ? data.Vertices.Length : mode == "Edge" ? ModelGeometryOperations.Edges(data.Faces).Count : data.Faces.Length; int[] old = session.Get("elements").AsInt32Array(); var selected = old.ToList();
            if (command == "Select all" || command == "Invert selection") { var previous = new HashSet<int>(old); selected = Enumerable.Range(0, count).Where(index => command == "Select all" || !previous.Contains(index)).ToList(); }
            else if ((command == "Select similar normals" || command == "Select material") && mode == "Face" && old.Length > 0)
            { var chosen = new HashSet<int>(old); Vector3 normal = data.Normal(old[0]); for (int f = 0; f < data.Faces.Length; f++) if ((command == "Select similar normals" ? data.Normal(f).Dot(normal) > .98f : data.Materials[f] == data.Materials[old[0]]) && chosen.Add(f)) selected.Add(f); }
            else selected = _selection.expand(mesh, mode, old, command).ToList(); session.Set("elements", selected.ToArray());
        }
        session.EmitSignal("changed");
    }
    public void separate(Control workspace)
    {
        var session = Session(workspace); var item = session.Call("primary").As<Resource>(); int[] selected = session.Get("elements").AsInt32Array(); if (item == null || session.Get("mode").AsString() != "Face" || selected.Length == 0) { Status(workspace, "Select faces to separate."); return; }
        Action(session, "Separate faces", () => { var copy = _components.copy_component(item, true); copy.Set("title", copy.Get("title").AsString() + " separated"); copy.Get("modifiers").AsGodotArray().Clear(); copy.Set("generator", ""); var mesh = item.Get("mesh").As<Resource>(); var chosen = new HashSet<int>(selected); int[] remove = Enumerable.Range(0, mesh.Get("faces").AsGodotArray().Count).Where(index => !chosen.Contains(index)).ToArray(); copy.Set("mesh", _geometry.remove_faces(mesh, remove)); item.Set("mesh", _geometry.remove_faces(mesh, selected)); item.Set("generator", ""); session.Get("document").As<Resource>().Get("components").AsGodotArray().Add(copy); var selection = session.Get("selected").AsGodotArray<string>(); selection.Clear(); selection.Add(copy.Get("id").AsString()); session.Set("elements", Array.Empty<int>()); });
    }
    public void center_origin(Control workspace)
    { var session = Session(workspace); var item = session.Call("primary").As<Resource>(); var mesh = item?.Get("mesh").As<Resource>(); if (mesh != null) Action(session, "Center origin", () => item!.Set("pivot", _meshes.bounds(mesh).GetCenter())); }
    public void view_command(Control workspace, int index)
    {
        var canvas = workspace.Get("canvas").As<Control>(); var camera = canvas.Get("camera").As<Camera3D>();
        void Toggle(string field) => canvas.Set(field, !canvas.Get(field).AsBool());
        switch (index)
        {
            case 0: canvas.Call("frame", false); break; case 1: canvas.Call("frame", true); break; case 2: camera.Projection = camera.Projection == Camera3D.ProjectionType.Perspective ? Camera3D.ProjectionType.Orthogonal : Camera3D.ProjectionType.Perspective; break;
            case 9: var grid = canvas.Get("grid").As<Node3D>(); grid.Visible = !grid.Visible; break; case 10: Toggle("show_edges"); break; case 11: Toggle("wireframe"); canvas.Call("request_sync"); break; case 12: Toggle("xray"); canvas.Call("request_sync"); break; case 13: Toggle("show_normals"); break;
            case 14: var hierarchy = workspace.Get("hierarchy").As<Control>(); hierarchy.Visible = !hierarchy.Visible; break; case 15: var inspector = workspace.Get("_inspector_tabs").As<Control>(); inspector.Visible = !inspector.Visible; break;
            default: canvas.Call("set_view", new[] { "Front", "Back", "Left", "Right", "Top", "Bottom" }[index - 3]); break;
        }
        canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public void operation_dialog(Control workspace, string kind)
    {
        var session = Session(workspace); var popup = new PopupPanel { Name = "GeometryOperation" }; workspace.AddChild(popup); var fields = new VBoxContainer { CustomMinimumSize = new Vector2(280, 100) }; popup.AddChild(fields); workspace.Call("_label", fields, kind + " · live preview");
        var amount = new DragNumber(); amount.Name = "Distance"; amount.MinValue = kind.StartsWith("Extrude", StringComparison.Ordinal) ? -100 : .00001; amount.MaxValue = 100; amount.Step = .01; amount.Value = kind == "Weld" ? .0001 : .2; fields.AddChild(amount);
        var before = session.Call("snapshot").AsGodotDictionary(); bool accepted = false, closed = false; workspace.Set("_property_gesture", true);
        bool Live() => GodotObject.IsInstanceValid(workspace) && workspace.IsInsideTree();
        bool Current() => Live() && Session(workspace) == session;
        void Preview(double value) { if (!Current() || closed) return; session.Call("restore", before); string error = session.Call("edit_mesh", kind, value, true).AsString(); if (error.Length > 0) Status(workspace, error); }
        void Close(bool free)
        {
            if (closed) return; closed = true; if (Live()) { if (Current() && !accepted) session.Call("restore", before); workspace.Set("_property_gesture", false); workspace.Set("_refresh_pending", true); } before.Clear(); before.Dispose(); if (free && !popup.IsQueuedForDeletion()) popup.QueueFree();
        }
        Preview(amount.Value); amount.ValueChanged += Preview; amount.Connect("preview_changed", Callable.From<double>(Preview)); var row = new HBoxContainer(); fields.AddChild(row); var cancel = new Button { Text = "Cancel" }; row.AddChild(cancel); cancel.Pressed += popup.Hide; var apply = new Button { Text = "Apply" }; row.AddChild(apply);
        apply.Pressed += () => { if (!Current() || closed) { popup.Hide(); return; } accepted = true; session.Call("restore", before); workspace.Set("_last_geometry", kind); workspace.Set("_last_amount", amount.Value); Status(workspace, session.Call("edit_mesh", kind, amount.Value, false).AsString()); popup.Hide(); };
        popup.PopupHide += () => Close(true); popup.TreeExiting += () => Close(false); popup.PopupCentered(new Vector2I(320, 155));
    }
}
