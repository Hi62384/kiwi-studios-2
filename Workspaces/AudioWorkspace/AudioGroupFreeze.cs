using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioGroupFreeze : RefCounted
{
    public static Settings members(RefCounted document,string root)
    {using var operations=new AudioGroupFreezeOperations();return operations.members(document,root);}
    public static string apply(RefCounted session,string root,AudioStream stream)
    {using var operations=new AudioGroupFreezeOperations();return operations.apply(session,root,stream);}
    public static void restore_members(RefCounted document,Settings original)
    {using var operations=new AudioGroupFreezeOperations();operations.restore_members(document,original);}
}
