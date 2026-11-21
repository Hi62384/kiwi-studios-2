using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioLayerBundle : RefCounted
{
    public static Settings selected(RefCounted document,Godot.Collections.Array ids)
    {using var operations=new AudioLayerBundleOperations();return operations.selected(document,ids);}
    public static string insert(RefCounted session,RefCounted bundle,double at)
    {using var operations=new AudioLayerBundleOperations();return operations.insert(session,bundle,at);}
    public static string _rebase_owner(Settings owner,double origin)
    {using var operations=new AudioLayerBundleOperations();return operations.rebase_owner(owner,origin);}
}
