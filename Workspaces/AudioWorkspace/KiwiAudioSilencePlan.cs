using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioSilencePlan : RefCounted
{
    public WeakRef? _owner {get;set;}
    public WeakRef? _document {get;set;}
    public long _revision {get;set;}
    public string _clip_id {get;set;}="";
    public string _identity {get;set;}="";
    public GArray _geometry {get;set;}=new();
    public Settings _values {get;set;}=new();
    public Godot.Collections.Array<Settings> _regions {get;set;}=new();
    public Godot.Collections.Array<Settings> _cuts {get;set;}=new();
    public double _source_duration {get;set;}
    public bool _closed {get;set;}
    private readonly AudioEditSessionOperations _operations=new();
    public void cancel()=>_closed=true;
    public Godot.Collections.Array<Settings> regions()=>_regions.Duplicate(true);
    public Godot.Collections.Array<Settings> cuts()=>_cuts.Duplicate(true);
    public string clip_id()=>_clip_id;
    public bool current(KiwiAudioEditSession session)=>_operations.silence_plan_current(this,session);
}
