using Godot;

[GlobalClass]
public partial class WorldSeed : RefCounted
{
    public static Resource apply(Resource source, long seed) => new WorldSeedOperations().apply(source, seed);
}
