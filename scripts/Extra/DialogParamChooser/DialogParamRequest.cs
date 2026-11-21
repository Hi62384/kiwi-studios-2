using Godot;
using Settings = Godot.Collections.Dictionary;

public partial class DialogParamRequest : RefCounted
{
    [Signal] public delegate void completedEventHandler(Settings result);
    public void Complete(Settings result) => EmitSignal("completed", result);
}
