using Godot;
using Settings = Godot.Collections.Dictionary;
public partial class ClipboardStoreRestoreAction : RefCounted
{
    private WeakRef? _owner;
    private Settings _before = new(), _after = new();
    public void initialize(RefCounted owner, Settings before, Settings after) { _owner = GodotObject.WeakRef(owner); _before = before; _after = after; }
    private void Restore(Settings value)
    {
        var owner = _owner?.GetRef().AsGodotObject() as RefCounted;
        if (GodotObject.IsInstanceValid(owner)) new ClipboardStoreOperations().assign(owner!, value);
    }
    public void restore_before() => Restore(_before);
    public void restore_after() => Restore(_after);
}
