using Godot;

[GlobalClass]
public partial class WorldBuildingMassingApi : RefCounted
{
    public static KiwiModelMesh mesh(Resource source) => (KiwiModelMesh)new WorldBuildingMassing().mesh(source);
}
