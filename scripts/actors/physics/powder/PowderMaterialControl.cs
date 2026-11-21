using Godot;

[GlobalClass]
public partial class PowderMaterialControl : VBoxContainer
{
    private readonly PowderMaterialControlOperations _operations = new();
    public void setup(ActorTimeline model, ActorData actor, Variant refresh) => _operations.setup(this, model, actor, refresh);
    public static Texture2D thumbnail(int index) => new PowderMaterialControlOperations().thumbnail(index);
    public void _refresh(Variant callback)
    {
        using var arguments = new Godot.Collections.Array();
        using var ignored = EngineVariantDispatch.InvokeCallable(callback, arguments);
    }
}
