using Godot;

[GlobalClass]
public partial class EnvironmentWorldOverrideApi : RefCounted
{
    public static void attach(Node3D runtime) => new EnvironmentActorOperations().attach_world(runtime);
}
