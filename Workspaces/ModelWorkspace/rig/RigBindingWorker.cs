using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;

public partial class RigBindingWorker : Node
{
    [Signal] public delegate void updatedEventHandler();
    [Signal] public delegate void finishedEventHandler();
    public RigWeightJob? job { get; private set; }
    public Godot.GodotThread? worker { get; private set; }
    private Control? _workspace;
    private RigEditor? _activeEditor;
    private int _generation;
    private readonly RigBindingImport _importer = new();
    public void configure(Control workspace) => _workspace = workspace;
    public override void _ExitTree() => cancel_job();
    private bool Live() => GodotObject.IsInstanceValid(this) && IsInsideTree() && GodotObject.IsInstanceValid(_workspace);
    private void Refresh() { if (Live()) EmitSignal(SignalName.updated); }
    private RigEditor? CurrentEditor()
    {
        if (_workspace == null || !GodotObject.IsInstanceValid(_workspace)) return null;
        var canvas = _workspace.Get("canvas").As<Control>(); if (!GodotObject.IsInstanceValid(canvas)) return null;
        var tool = canvas.Get("rig_tool").As<RefCounted>(); var proxy = tool?.Get("editor").As<RefCounted>();
        return proxy?.Get("_native").As<RigEditor>();
    }
    public bool start_binding(RigEditor editor, string style)
    {
        if (worker != null || !Live() || _workspace == null) return false;
        if (style == "Rigid") { editor.message = editor.bind(style, 4); Refresh(); return false; }
        var armature = editor.rig(); var targets = editor.meshes();
        if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) { editor.message = "Create bones first."; Refresh(); return false; }
        if (targets.Count == 0) { editor.message = "Select meshes to bind."; Refresh(); return false; }
        var session = _workspace.Get("session").As<RefCounted>(); var document = session.Get("document").As<Resource>();
        long revision = session.Get("revision").AsInt64(), signature = session.Call("_signature", document).AsInt64(); string rigId = armature.Get("id").AsString();
        var prepared = _importer.prepare_tasks(document, armature, new Godot.Collections.Array(targets.Select(value => Variant.From(value))));
        if (prepared["message"].AsString().Length > 0) { editor.message = prepared["message"].AsString(); Refresh(); return false; }
        job = new RigWeightJob { method = style, tasks = prepared["tasks"].AsGodotArray<Settings>() }; worker = new Godot.GodotThread();
        Error error = worker.Start(new Callable(job, "run"));
        if (error != Error.Ok) { editor.message = "Could not start weight calculation (" + (int)error + ")."; worker = null; job = null; Refresh(); return false; }
        _activeEditor = editor; editor.busy = true; editor.message = "Calculating weights… Cancel is available."; int generation = ++_generation; Refresh();
        _ = Complete(job, worker, editor, session, revision, signature, rigId, generation, GetTree()); return true;
    }
    private async Task Complete(RigWeightJob task, Godot.GodotThread started, RigEditor ownedEditor, RefCounted ownedSession, long revision, long signature, string rigId, int generation, SceneTree tree)
    {
        try
        {
            // Always yield once so GDScript callers can await finished, even for tiny jobs.
            await ToSignal(tree, SceneTree.SignalName.ProcessFrame);
            while (generation == _generation && started.IsAlive()) await ToSignal(tree, SceneTree.SignalName.ProcessFrame);
            if (generation != _generation || !Live()) return;
            var returned = started.WaitToFinish(); worker = null; ownedEditor.busy = false;
            var bindings = returned.VariantType == Variant.Type.Dictionary ? returned.AsGodotDictionary() : new Settings();
            var current = CurrentEditor() ?? ownedEditor;
            if (task.is_cancelled()) current.message = "Weight calculation canceled. Nothing changed.";
            else if (_workspace!.Get("session").As<RefCounted>().GetInstanceId() != ownedSession.GetInstanceId()
                || ownedSession.Get("revision").AsInt64() != revision || ownedSession.Get("_gesture").AsGodotDictionary().Count > 0
                || ownedSession.Call("_signature", ownedSession.Get("document")).AsInt64() != signature) current.message = "Model changed during calculation; stale weights discarded.";
            else current.message = current.install_bindings(rigId, bindings);
            if (generation != _generation || !Live()) return;
            job = null; _activeEditor = null; Refresh(); EmitSignal(SignalName.finished);
        }
        catch (Exception error)
        {
            if (generation != _generation) return;
            task.cancel(); if (started.IsStarted()) started.WaitToFinish(); worker = null; job = null; ownedEditor.busy = false; _activeEditor = null;
            if (Live()) { (CurrentEditor() ?? ownedEditor).message = "Weight calculation failed: " + error.Message; Refresh(); EmitSignal(SignalName.finished); }
            GD.PushError(error.ToString());
        }
    }
    public void cancel_job()
    {
        bool pending = worker != null; ++_generation; job?.cancel();
        if (worker != null && worker.IsStarted()) worker.WaitToFinish(); worker = null; job = null;
        if (_activeEditor != null) _activeEditor.busy = false; _activeEditor = null;
        if (pending && GodotObject.IsInstanceValid(this) && IsInsideTree()) EmitSignal(SignalName.finished);
    }
}
