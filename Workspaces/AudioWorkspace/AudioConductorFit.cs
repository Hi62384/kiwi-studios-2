using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioConductorFit : RefCounted
{
    public static Settings prepare(RefCounted session,Godot.Collections.Array ids)
    { using var operations=new AudioConductorFitOperations(); return operations.prepare(session,ids); }
    public static string apply(RefCounted session,Godot.Collections.Array ids)
    { using var operations=new AudioConductorFitOperations(); return operations.apply(session,ids); }
}
