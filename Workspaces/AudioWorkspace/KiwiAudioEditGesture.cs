using Godot;
[GlobalClass]
public partial class KiwiAudioEditGesture : RefCounted
{
    public KiwiAudioEditSession? owner {get;set;}
    public KiwiAudioDocument? document {get;set;}
    public KiwiAudioDocument? before {get;set;}
    private readonly AudioEditSessionOperations _operations=new();
    public bool valid(KiwiAudioEditSession? current)=>_operations.gesture_valid(this,current);
    public void clear()=>_operations.gesture_clear(this);
    public void begin(KiwiAudioEditSession current,string label)=>_operations.gesture_begin(this,current,label);
    public void finish(KiwiAudioEditSession? current)=>finish(current,true);
    public void finish(KiwiAudioEditSession? current,bool keep)=>_operations.gesture_finish(this,current,keep);
}
