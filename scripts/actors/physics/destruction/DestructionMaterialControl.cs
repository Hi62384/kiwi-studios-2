using Godot;

[GlobalClass]
public partial class DestructionMaterialControl : HBoxContainer
{
    public void setup(Control host, ActorData actor) => new DestructionMaterialControlOperations().setup(this, host, actor);
}
