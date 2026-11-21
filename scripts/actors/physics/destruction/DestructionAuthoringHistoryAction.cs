using Godot;
using GArray=Godot.Collections.Array;
public partial class DestructionAuthoringHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly Resource? _actor;private readonly StringName _field=new("");private readonly Variant _before,_after;private readonly GArray? _beforeTracks,_afterTracks;private readonly bool _whole;private readonly DestructionAuthoringOperations _operations=new();
    public DestructionAuthoringHistoryAction(){}
    public DestructionAuthoringHistoryAction(RefCounted model,Resource actor,StringName field,Variant before,Variant after,GArray? beforeTracks,GArray? afterTracks,bool whole){_model=GodotObject.WeakRef(model);_actor=actor;_field=field;_before=before;_after=after;_beforeTracks=beforeTracks;_afterTracks=afterTracks;_whole=whole;}
    private void Restore(Variant value,GArray? tracks){if(_model==null||_actor==null)return;if(_whole){if(tracks==null)_operations.assign_values(_model,_actor,value.AsGodotDictionary());else _operations.assign_setup(_model,_actor,value.AsGodotDictionary(),tracks);}else if(tracks==null)_operations.assign(_model,_actor,_field,value);else _operations.restore_fragments(_model,_actor,_field,value.AsGodotDictionary(),tracks);}
    public void restore_before()=>Restore(_before,_beforeTracks);public void restore_after()=>Restore(_after,_afterTracks);
}
