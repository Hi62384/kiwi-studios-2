using Godot;
using GArray=Godot.Collections.Array;
// The history retains its snapshots and action, while the model reference stays weak.
public partial class ActorPropertyBatchRestoreAction:RefCounted
{
    private readonly WeakRef? _model;private readonly GArray? _before,_after;private readonly ActorDataOperations _data=new();
    public ActorPropertyBatchRestoreAction(){}
    public ActorPropertyBatchRestoreAction(RefCounted model,GArray before,GArray after){_model=GodotObject.WeakRef(model);_before=before;_after=after;}
    private void Restore(GArray? state){if(_model==null||state==null)return;using var reference=_model.GetRef();if(reference.AsGodotObject() is RefCounted model&&GodotObject.IsInstanceValid(model))ActorPropertyBatchOperations.RestoreModel(model,state,_data);}
    public void restore_before()=>Restore(_before);
    public void restore_after()=>Restore(_after);
}
