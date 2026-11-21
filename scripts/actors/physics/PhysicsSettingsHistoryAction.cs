using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class PhysicsSettingsHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly Resource? _actor;private readonly Settings? _before,_after;private readonly PhysicsSettingsOperations _operations=new();
    public PhysicsSettingsHistoryAction(){}
    public PhysicsSettingsHistoryAction(RefCounted model,Resource actor,Settings before,Settings after){_model=GodotObject.WeakRef(model);_actor=actor;_before=before;_after=after;}
    private void Restore(Settings? state){if(_model==null||_actor==null||state==null)return;using var reference=_model.GetRef();if(reference.AsGodotObject() is RefCounted model&&GodotObject.IsInstanceValid(model))_operations.assign(model,_actor,state);}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
}
