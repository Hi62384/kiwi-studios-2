using Godot;
using System;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceBooleanJob : Node
{
    [Signal] public delegate void completedEventHandler();
    private Control? _workspace;
    private RefCounted? _ownedSession;
    private long _ownedRevision;
    private bool _running;
    private readonly ModelModifiers _modifiers = new();
    private readonly ModelMeshOperations _meshes = new();
    private bool Live() => GodotObject.IsInstanceValid(this) && IsInsideTree() && !IsQueuedForDeletion() && GodotObject.IsInstanceValid(_workspace) && _workspace!.IsInsideTree() && !_workspace.IsQueuedForDeletion();
    public void start(Control workspace, string command) { if (_running) return; _workspace = workspace; _ownedSession = workspace.Get("session").As<RefCounted>(); _ownedRevision = _ownedSession.Get("revision").AsInt64(); _running = true; _ = Run(command, GetTree()); }
    private void Status(string text) { if (Live()) _workspace!.Get("status").As<Label>().Text = text; }
    private void Finish() { if (!_running) return; _running = false; EmitSignal(SignalName.completed); if (Live()) QueueFree(); }
    public override void _ExitTree() { if (_running) { _running = false; EmitSignal(SignalName.completed); } _workspace = null; _ownedSession = null; }
    private async Task Run(string command, SceneTree tree)
    {
        Settings? before = null;
        try
        {
            await ToSignal(tree, SceneTree.SignalName.ProcessFrame); if (!Live() || _workspace!.Get("session").As<RefCounted>() != _ownedSession || _ownedSession.Get("revision").AsInt64() != _ownedRevision) return;
            var workspace = _workspace!; var session = workspace.Get("session").As<RefCounted>(); var selected = session.Get("selected").AsGodotArray<string>(); if (selected.Count != 2) { Status("Select the target, then the cutter. The last selected mesh is the cutter."); return; }
            var document = session.Get("document").As<Resource>(); var lookup = ModelDocumentOperations.Lookup(document); var a = lookup[selected[0]]; var b = session.Call("primary").As<Resource>(); if (a.Get("mesh").As<Resource>() == null || b.Get("mesh").As<Resource>() == null) return;
            using var first = _modifiers.evaluate(a); using var second = _modifiers.evaluate(b); if (first.Get("faces").AsGodotArray().Count + second.Get("faces").AsGodotArray().Count > 2500) { Status("Boolean limited to 2,500 evaluated input faces for responsive editing."); return; }
            long revision = session.Get("revision").AsInt64(); string aId = a.Get("id").AsString(), bId = b.Get("id").AsString(); Status("Evaluating Boolean…"); before = session.Call("snapshot").AsGodotDictionary(); workspace.MouseFilter = Control.MouseFilterEnum.Stop;
            int mode = (int)(command == "Boolean difference" ? CsgShape3D.OperationEnum.Subtraction : command == "Boolean union" ? CsgShape3D.OperationEnum.Union : CsgShape3D.OperationEnum.Intersection); var operation = new ModelBooleanOperation(); AddChild(operation);
            if (!operation.start(first, second, ModelDocumentOperations.WorldTransform(lookup, a).AffineInverse() * ModelDocumentOperations.WorldTransform(lookup, b), mode, a.Get("surface_materials").AsGodotArray<Material>(), b.Get("surface_materials").AsGodotArray<Material>())) { Status("Boolean failed or produced an empty result; sources kept."); return; }
            await ToSignal(operation, ModelBooleanOperation.SignalName.completed); if (!Live() || !workspace.IsVisibleInTree() || workspace.Get("session").As<RefCounted>() != session || session.Get("revision").AsInt64() != revision) return;
            var mesh = operation.result; if (mesh == null || _meshes.validate(mesh, true).Length > 0) { Status("Boolean failed or produced an empty result; sources kept."); return; }
            session.Call("restore", before); session.Call("begin");
            try
            {
                var current = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); var target = current[aId]; target.Set("mesh", mesh); var materials = target.Get("surface_materials").AsGodotArray<Material>(); materials.Clear(); foreach (Variant material in mesh.GetMeta("boolean_materials", new Godot.Collections.Array()).AsGodotArray()) materials.Add(material.As<Material>()); mesh.RemoveMeta("boolean_materials"); target.Set("generator", ""); target.Get("modifiers").AsGodotArray().Clear(); current[bId].Set("visible", false); selected = session.Get("selected").AsGodotArray<string>(); selected.Clear(); selected.Add(aId); session.Set("elements", Array.Empty<int>()); session.Call("commit", command);
            }
            catch { session.Call("cancel"); throw; }
            Status("Boolean baked to editable geometry. Cutter kept hidden.");
        }
        catch (Exception error) { if (Live()) { Status("Boolean failed; sources kept."); GD.PushError(error.ToString()); } }
        finally { if (before != null) { before.Clear(); before.Dispose(); } _ownedSession = null; if (GodotObject.IsInstanceValid(this)) Finish(); }
    }
}
