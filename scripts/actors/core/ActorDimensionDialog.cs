using Godot;

[GlobalClass]
public partial class ActorDimensionDialog : AcceptDialog
{
    [Signal] public delegate void choice_madeEventHandler(StringName choice);
    private bool _finished;
    public static Variant choose(Node owner, string asset)
    {
        if (DisplayServer.GetName() == "headless") return new StringName("3d");
        var dialog = new ActorDimensionDialog();
        dialog.choice_made += dialog.FinishChoice;
        owner.AddChild(dialog);
        dialog.build(asset);
        dialog.PopupCentered(new Vector2I(430, 210));
        // A native Signal preserves `await choose(...)` for remaining GD callers.
        return Variant.From(new Signal(dialog, "choice_made"));
    }
    public void build(string asset) => new ActorFontPickerOperations().build_dimension(this, asset);
    private void FinishChoice(StringName choice)
    {
        if (_finished) return;
        _finished = true;
        if (!IsQueuedForDeletion()) QueueFree();
    }
    public override void _ExitTree()
    {
        if (!_finished) EmitSignal("choice_made", new StringName(""));
    }
}
