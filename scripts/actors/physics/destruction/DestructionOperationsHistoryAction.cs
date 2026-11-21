using Godot;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class DestructionOperationsHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly Resource? _actor;private readonly Settings? _before,_after;private readonly GArray? _beforeTracks,_afterTracks;private readonly DestructionDefinitionOperations _operations=new();
    public DestructionOperationsHistoryAction(){}
    public DestructionOperationsHistoryAction(RefCounted model,Resource actor,Settings before,GArray beforeTracks,Settings after,GArray afterTracks){_model=GodotObject.WeakRef(model);_actor=actor;_before=before;_after=after;_beforeTracks=beforeTracks;_afterTracks=afterTracks;}
    private void Restore(Settings? values,GArray? tracks){if(_model!=null&&_actor!=null&&values!=null&&tracks!=null)_operations.restore_animation(_model,_actor,values,tracks);}
    public void restore_before()=>Restore(_before,_beforeTracks);public void restore_after()=>Restore(_after,_afterTracks);
}
