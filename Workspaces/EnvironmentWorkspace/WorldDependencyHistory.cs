using Godot;
using Settings=Godot.Collections.Dictionary;

/// <summary>Combines dependent snapshots with the original sparse history callbacks.</summary>
public partial class WorldDependencyHistory : RefCounted
{
    public RefCounted? session {get;set;}
    public Settings before {get;set;}=new();
    public Settings after {get;set;}=new();
    public Settings callbacks {get;set;}=new();
    public void undo(){session!.Call("restore",before);GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").Call("_invoke_callback",callbacks,"undo");}
    public void redo(){GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").Call("_invoke_callback",callbacks,"redo");session!.Call("restore",after);}
}
