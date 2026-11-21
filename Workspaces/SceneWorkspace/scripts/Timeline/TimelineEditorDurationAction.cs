using Godot;
public partial class TimelineEditorDurationAction:RefCounted
{
    private readonly WeakRef _owner;private readonly double _before,_after;
    public TimelineEditorDurationAction(Control owner,double before,double after){_owner=GodotObject.WeakRef(owner)??throw new System.InvalidOperationException("Cannot retain timeline editor");_before=before;_after=after;}
    public void restore_before()=>Apply(_before);public void restore_after()=>Apply(_after);private void Apply(double value){var owner=_owner.GetRef().AsGodotObject() as Control;if(!GodotObject.IsInstanceValid(owner))return;owner!.Set("_video_duration_override",value);owner.Get("model").AsGodotObject().EmitSignal("changed");}
}
