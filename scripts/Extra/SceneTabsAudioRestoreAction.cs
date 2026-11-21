using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class SceneTabsAudioRestoreAction:RefCounted
{
    private readonly WeakRef _model;private readonly Settings _before,_after;private readonly ActorTimelineOperations _timeline=new();
    public SceneTabsAudioRestoreAction(RefCounted model,Settings before,Settings after){_model=GodotObject.WeakRef(model)??throw new System.InvalidOperationException("Cannot retain audio destination");_before=before;_after=after;}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);private void Restore(Settings value){var model=_model.GetRef().AsGodotObject() as RefCounted;if(GodotObject.IsInstanceValid(model))_timeline.restore_audio(model!,value);}
}
