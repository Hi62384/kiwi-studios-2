using Godot;

[GlobalClass]
public partial class TerrainWaterfallApi : RefCounted
{
    public static void sync(MeshInstance3D water, Resource terrain) => new TerrainWaterfallRender().sync(water, terrain);
}
