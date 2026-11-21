using Godot;

[GlobalClass]
public partial class KiwiModelSelection : RefCounted
{
    public static int[] expand(KiwiModelMesh mesh, string mode, int[] selected, string operation) => new ModelSelection().expand(mesh, mode, selected, operation);
}
