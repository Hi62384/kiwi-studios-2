using Godot;

[GlobalClass]
public partial class RoadFollow : RefCounted
{
    public static void controls(Resource source) => new WorldPlacementOperations().follow_controls(source);
}
