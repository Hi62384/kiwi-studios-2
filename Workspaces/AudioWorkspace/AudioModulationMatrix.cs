using Godot;
[GlobalClass]
public partial class AudioModulationMatrix : RefCounted
{
    public static string apply(RefCounted session,Godot.Collections.Array rows)
    { using var operations=new AudioModulationMatrixOperations(); return operations.apply(session,rows); }
}
