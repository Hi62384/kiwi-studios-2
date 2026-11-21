using Godot;

[GlobalClass]
public partial class WorldMeshStamp : RefCounted
{
    public static long value(KiwiModelMesh mesh, int version = 2) => new WorldBuildingMassing().stamp(mesh, version);
}
