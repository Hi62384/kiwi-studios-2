using Godot;

[GlobalClass]
public partial class TerrainLod : RefCounted
{
    public static ArrayMesh? prepare(ArrayMesh? source) => new TerrainMeshLod().prepare(source);
}
