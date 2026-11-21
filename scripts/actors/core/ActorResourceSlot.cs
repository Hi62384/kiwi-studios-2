using Godot;

[GlobalClass]
public partial class ActorResourceSlot : Button
{
    [Signal] public delegate void file_droppedEventHandler(string path);
    public Variant accepts_file { get; set; }
    private readonly ActorResourceSlotOperations _operations = new();
    public override bool _CanDropData(Vector2 atPosition, Variant data) => _operations.can_drop(this, data);
    public override void _DropData(Vector2 atPosition, Variant data) => _operations.drop(this, data);
    public override void _Notification(int what) => _operations.drag_notification(this, what);
    public static string path_from_drag(Variant data) => new ActorResourceSlotOperations().path_from_drag(data);
    public static string _normalize_path(string path) => new ActorResourceSlotOperations().normalize_path(path);
    public bool _accept_path(string path)
    {
        if (!EngineVariantDispatch.CallableValid(accepts_file)) return true;
        using var arguments = new Godot.Collections.Array { path };
        using var result = EngineVariantDispatch.InvokeCallable(accepts_file, arguments);
        return result.AsBool();
    }
}
