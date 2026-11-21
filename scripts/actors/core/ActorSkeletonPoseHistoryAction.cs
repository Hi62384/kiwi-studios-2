using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class ActorSkeletonPoseHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly Settings? _before,_after;private readonly ActorSkeletonPoseOperations _operations=new();
    public ActorSkeletonPoseHistoryAction(){}
    public ActorSkeletonPoseHistoryAction(RefCounted model,Settings before,Settings after){_model=GodotObject.WeakRef(model);_before=before;_after=after;}
    private void Restore(Settings? state){if(_model==null||state==null)return;using var reference=_model.GetRef();if(reference.AsGodotObject() is RefCounted model&&GodotObject.IsInstanceValid(model))_operations.restore(model,state);}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
}
