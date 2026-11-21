using Godot;

[GlobalClass]
public partial class EnvironmentWaterApi : RefCounted
{
    public static void sync(Node3D node, Resource terrain) => new EnvironmentWaterRender().sync(node, terrain);
}
