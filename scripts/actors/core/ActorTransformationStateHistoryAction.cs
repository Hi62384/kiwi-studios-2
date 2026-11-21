using Godot;
using GArray=Godot.Collections.Array;
public partial class ActorTransformationStateHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly GArray? _before,_after;private readonly ActorTransformationStateOperations _operations=new();
    public ActorTransformationStateHistoryAction(){}
    public ActorTransformationStateHistoryAction(RefCounted model,GArray before,GArray after){_model=GodotObject.WeakRef(model);_before=before;_after=after;}
    private void Restore(GArray? state){if(_model==null||state==null)return;using var reference=_model.GetRef();if(reference.AsGodotObject() is RefCounted model&&GodotObject.IsInstanceValid(model))_operations.restore(model,state);}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
}
