using Godot;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class DialogParamChooser : Control
{
    [Export] public Button? close_button { get; set; }
    [Export] public Button? select_button { get; set; }
    [Export] public Godot.Collections.Array<DialogParamChooserMapping> mappings { get; set; } = new();
    public Settings _state { get; set; } = new();
    public long _param_revision { get; set; }
    private sealed record Pending(DialogParamRequest Request, Settings State);
    private readonly List<Pending> _pending = new();
    private readonly SharedControlOperations _operations = new();
    public override void _Ready() { _operations.chooser_ready(this); SetProcess(_pending.Count > 0); }
    // A single-argument signal preserves `await chooser.select_params()` and its
    // Dictionary result. Each request has a separate signal, including stale calls.
    public Signal select_params()
    {
        var request = new DialogParamRequest();
        _pending.Add(new Pending(request, _operations.begin_params(this)));
        SetProcess(true);
        return new Signal(request, "completed");
    }
    private void Complete(Pending pending)
    {
        if (!_pending.Remove(pending)) return;
        var result = _operations.finish_params(this, pending.State);
        try { pending.Request.Complete(result); }
        finally { pending.Request.Dispose(); }
    }
    public override void _Process(double delta)
    {
        foreach (var pending in _pending.ToArray())
        {
            if (!GodotObject.IsInstanceValid(this) || !IsInsideTree()) return;
            if (_operations.params_done(this, pending.State)) Complete(pending);
        }
        if (GodotObject.IsInstanceValid(this) && IsInsideTree()) SetProcess(_pending.Count > 0);
    }
    public override void _ExitTree()
    {
        foreach (var pending in _pending.ToArray()) { pending.State["badboy"] = true; Complete(pending); }
        SetProcess(false);
    }
    public void _cancel_params() => _operations.chooser_decision(this, true);
    public void _confirm_params() => _operations.chooser_decision(this, false);
}
