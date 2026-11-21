using Godot;

// UndoRedo requires method-backed callables. The history owns this action,
// while the action deliberately holds only a weak reference to its session.
public partial class AudioHistoryRestoreAction : RefCounted
{
    private readonly WeakRef? _owner;
    private readonly GodotObject? _before;
    private readonly GodotObject? _after;
    public AudioHistoryRestoreAction() { }
    public AudioHistoryRestoreAction(RefCounted owner, GodotObject before, GodotObject after)
    {
        _owner=GodotObject.WeakRef(owner);_before=before;_after=after;
    }
    private void Restore(GodotObject? snapshot)
    {
        if(_owner==null||snapshot==null)return;
        using var reference=_owner.GetRef();
        if(reference.AsGodotObject() is RefCounted target&&GodotObject.IsInstanceValid(target))target.Call("_restore",snapshot);
    }
    public void restore_before()=>Restore(_before);
    public void restore_after()=>Restore(_after);
}
