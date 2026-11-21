using Godot;
using System;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceFileJob : Node
{
    [Signal] public delegate void completedEventHandler(long result);
    private Control? _workspace;
    private RefCounted? _session;
    private bool _running;
    private readonly ModelDocumentOperations _documents = new();
    private bool Live() => GodotObject.IsInstanceValid(this) && IsInsideTree() && !IsQueuedForDeletion() && GodotObject.IsInstanceValid(_workspace) && _workspace!.IsInsideTree() && !_workspace.IsQueuedForDeletion();
    private bool Current() => Live() && _workspace!.Get("session").As<RefCounted>() == _session;
    private void Status(string text) { if (Live()) _workspace!.Get("status").As<Label>().Text = text; }
    public void start(Control workspace, string mode, string destination)
    { if (_running) return; _workspace = workspace; _session = workspace.Get("session").As<RefCounted>(); _running = true; _ = Run(mode, destination, GetTree()); }
    private void Finish(Error error)
    { if (!_running) return; _running = false; EmitSignal(SignalName.completed, (long)error); if (Live()) QueueFree(); _session = null; }
    public override void _ExitTree() { if (_running) { _running = false; EmitSignal(SignalName.completed, (long)Error.Busy); } _workspace = null; _session = null; }
    private async Task<Variant> AwaitLegacy(string kind, GArray arguments)
    {
        if (!Live()) return default; var bridge = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>(); AddChild(bridge); bridge.Call("run", kind, _workspace!, arguments); var returned = await ToSignal(bridge, "completed"); return returned.Length > 0 ? returned[0] : default;
    }
    private async Task Run(string mode, string destination, SceneTree tree)
    {
        Error error = Error.Busy;
        try
        {
            await ToSignal(tree, SceneTree.SignalName.ProcessFrame); if (!Current()) return;
            if (mode == "open" || mode == "material") { error = await PickFile(mode); return; }
            if (mode == "save_to") error = await SaveTo(destination, tree);
            else
            {
                string path = _workspace!.Get("path").AsString();
                if (mode == "save_as" || path.Length == 0)
                {
                    var owned = _session!; string suggested = path.Length > 0 ? path.GetFile().GetBaseName() : "Model"; var picked = await AwaitLegacy("save_as", new GArray { suggested, Callable.From(() => owned.Get("document").As<Resource>().Call("snapshot")) }); if (!Current()) return;
                    var result = picked.VariantType == Variant.Type.Dictionary ? picked.AsGodotDictionary() : new Settings(); if (!result.TryGetValue("cancelled", out var cancelled) || cancelled.AsBool()) { error = Error.Ok; return; } path = result["path"].AsString();
                }
                error = await SaveTo(path, tree);
                if (mode == "scene" && error == Error.Ok && Current() && _workspace!.Get("path").AsString().Length > 0) _workspace.EmitSignal("use_in_scene", _workspace.Get("path"));
            }
        }
        catch (Exception failure) { if (Live()) { Status("File operation failed: " + failure.Message); GD.PushError(failure.ToString()); } error = Error.Failed; }
        finally { if (GodotObject.IsInstanceValid(this)) Finish(error); }
    }
    private async Task<Error> PickFile(string mode)
    {
        var property = new ActorProperty(); property.Set("options", mode == "open" ? new Settings { ["extensions"] = new[] { "tres", "res", "mesh", "glb", "gltf", "obj", "fbx" }, ["raw_extensions"] = new[] { "glb", "gltf", "obj", "fbx" }, ["native_resource_types"] = new[] { "KiwiModelDocument", "Mesh", "PackedScene" } } : new Settings { ["extensions"] = new[] { "tres", "res" }, ["native_resource_types"] = new[] { "Material" } });
        Variant selected = await AwaitLegacy("pick_file", new GArray { property, mode == "open" ? "Open editable model or import a mesh" : "Choose Material" }); if (!Current()) return Error.Busy; string path = selected.VariantType == Variant.Type.String ? selected.AsString() : ""; if (path.Length == 0 || path == "::empty-resource::") return Error.Ok;
        if (mode == "open") _workspace!.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("open_model", path);
        else if (ResourceLoader.Load(path) is Material material)
        {
            var session = _session!; var item = session.Call("primary").As<Resource>(); if (item != null) { session.Call("begin"); try { item.Get("surface_materials").AsGodotArray<Material>().Add(material); session.Call("commit", "Load material"); } catch { session.Call("cancel"); throw; } }
        }
        return Error.Ok;
    }
    private async Task<Error> SaveTo(string destination, SceneTree tree)
    {
        Variant flushed = await AwaitLegacy("flush", new GArray()); if (!Current() || flushed.VariantType != Variant.Type.Bool || !flushed.AsBool()) return Error.Busy; var workspace = _workspace!; var session = _session!; var canvas = workspace.Get("canvas").As<Control>(); canvas.Get("rig_tool").As<RefCounted>().Call("finish", false); canvas.Call("finish_transform", false); canvas.Call("finish_extrusion", false);
        var document = session.Get("document").As<Resource>(); document.Get("workspace_state").AsGodotDictionary().Merge(new Settings { ["view"] = canvas.Call("capture_state"), ["panels"] = workspace.Call("_capture_panels"), ["selected"] = session.Get("selected").AsGodotArray<string>().Duplicate(), ["mode"] = session.Get("mode"), ["elements"] = session.Get("elements").AsInt32Array(), ["rig"] = workspace.Call("_rig_state") }, true); string[] errors = _documents.validate(document); if (errors.Length > 0) { Status("Save cancelled: " + errors[0]); return Error.InvalidData; }
        canvas.Call("request_sync"); while (Current() && canvas.Get("_pending_sync").AsBool()) { canvas.Call("sync"); await ToSignal(tree, SceneTree.SignalName.ProcessFrame); } if (!Current()) return Error.Busy; long revision = session.Get("revision").AsInt64(); using var saved = _documents.snapshot(session.Get("document").As<Resource>());
        if (DisplayServer.GetName() != "headless")
        {
            // A minimized/static editor may not schedule another post-draw signal.
            // Preview uploads already yielded a frame; explicitly render them now.
            RenderingServer.ForceSync(); RenderingServer.ForceDraw(false); if (!Live()) return Error.Busy;
            if (Current()) { using var bitmap = canvas.Get("viewport").As<SubViewport>().GetTexture().GetImage(); double factor = Math.Min(240.0 / bitmap.GetWidth(), 180.0 / bitmap.GetHeight()); bitmap.Resize(Math.Max(1, (int)Math.Round(bitmap.GetWidth() * factor, MidpointRounding.AwayFromZero)), Math.Max(1, (int)Math.Round(bitmap.GetHeight() * factor, MidpointRounding.AwayFromZero)), Image.Interpolation.Lanczos); saved.Set("preview", default(Variant)); saved.Set("preview_png", bitmap.SavePngToBuffer()); }
        }
        if (!Live()) return Error.Busy; Error error = ResourceSaver.Save(saved, destination);
        if (error == Error.Ok)
        {
            if (session.Get("revision").AsInt64() == revision) session.Set("dirty", false); if (Current()) { workspace.Set("path", destination); workspace.Set("source", destination); Status("Saved " + destination); } workspace.EmitSignal("model_saved", destination, session); GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").Call("refresh_filesystem");
        }
        else Status("Save failed (" + (int)error + ")."); if (Live()) workspace.Set("_refresh_pending", true); return error;
    }
}
