using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class InspectorFilePropertyAction:RefCounted
{
    private readonly WeakRef _model;private readonly bool _notify;private readonly Resource _data,_root,_target;private readonly StringName _key;private readonly Variant _before,_after;private readonly ActorDataOperations _values=new();
    public InspectorFilePropertyAction(RefCounted model,Resource data,Resource root,Resource target,StringName key,Variant before,Variant after,bool notify=true){_notify=notify;_model=GodotObject.WeakRef(model)??throw new System.InvalidOperationException("Cannot retain editor model");_data=data;_root=root;_target=target;_key=key;_before=before;_after=after;}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
    private void Restore(Variant value){_values.set_value(_data,_key,_values.copy_value(value));_root.EmitChanged();if(_target.ResourcePath.Length>0)ResourceSaver.Save(_target,_target.ResourcePath);var model=_model.GetRef().AsGodotObject();if(_notify&&GodotObject.IsInstanceValid(model))model!.EmitSignal("changed");}
}
