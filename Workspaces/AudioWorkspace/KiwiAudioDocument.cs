using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioDocument : Resource
{
    public const int CURRENT_VERSION=1;
    [Export] public int version {get;set;}=CURRENT_VERSION;
    [Export] public string title {get;set;}="Untitled Audio";
    [Export] public Godot.Collections.Array<ActorData> actors {get;set;}=new();
    [Export] public Godot.Collections.Array<ActorClip> clips {get;set;}=new();
    [Export] public Godot.Collections.Array<Settings> tracks {get;set;}=new();
    [Export] public double tempo {get;set;}=120;
    [Export] public Vector2I time_signature {get;set;}=new(4,4);
    [Export] public Godot.Collections.Array<Settings> tempo_points {get;set;}=new();
    [Export] public Godot.Collections.Array<Settings> meter_points {get;set;}=new();
    [Export] public double note_base_tempo {get;set;}
    [Export] public Vector2I note_base_meter {get;set;}
    [Export] public int key {get;set;}
    [Export] public string scale {get;set;}="minor";
    [Export] public Godot.Collections.Array<Settings> markers {get;set;}=new();
    [Export] public Godot.Collections.Array<Settings> sections {get;set;}=new();
    [Export] public GArray chords {get;set;}=new();
    [Export] public Settings composer_settings {get;set;}=new();
    [Export] public Settings master {get;set;}=new(){["volume_db"]=-3.0,["effects"]=new GArray(),["automation"]=new Settings()};
    [Export] public double loop_start {get;set;}
    [Export] public double loop_end {get;set;}=4;
    [Export] public bool loop_enabled {get;set;}
    [Export] public Settings presets {get;set;}=new();
    [Export] public Godot.Collections.Array<Settings> takes {get;set;}=new();
    [Export] public Settings workspace_state {get;set;}=new();
    [Export] public string output_path {get;set;}="";
    [Export] public Settings scene_binding {get;set;}=new();
    [Export] public Settings portable_media {get;set;}=new();
    public string _portable_root {get;set;}="";
    private readonly AudioDocumentOperations _operations=new();
    public Settings add_track()=>add_track("Audio","audio");
    public Settings add_track(string label)=>add_track(label,"audio");
    public Settings add_track(string label,string kind)=>_operations.add_track(this,label,kind);
    public Settings track_for_id(string id)=>_operations.track_for_id(this,id);
    public ActorData? actor_for_clip(string id)=>_operations.actor_for_clip(this,id) as ActorData;
    public ActorClip? clip_for_id(string id)=>_operations.clip_for_id(this,id) as ActorClip;
    public Settings track_for_clip(string id)=>_operations.track_for_clip(this,id);
    public KiwiAudioConductor conductor()=>(KiwiAudioConductor)_operations.conductor(this);
    public double note_tempo()=>_operations.note_tempo(this);
    public Vector2I note_meter()=>_operations.note_meter(this);
    public double arrangement_tempo()=>_operations.arrangement_tempo(this);
    public double duration()=>_operations.duration(this);
    public KiwiAudioDocument snapshot()=>(KiwiAudioDocument)_operations.snapshot(this);
    public string[] validate()=>_operations.validate(this);
    public string midi_timing_error()=>midi_timing_error(new GArray(),"",default);
    public string midi_timing_error(GArray additional)=>midi_timing_error(additional,"",default);
    public string midi_timing_error(GArray additional,string replaced_actor_id)=>midi_timing_error(additional,replaced_actor_id,default);
    public string midi_timing_error(GArray additional,string replaced_actor_id,Variant legacy_override)=>_operations.midi_timing_error(this,additional,replaced_actor_id,legacy_override);
    public static bool _number_in(Variant value,double low,double high)
    {using var operations=new AudioDocumentOperations();return operations.number_in(value,low,high);}
    public static void _validate_owner(Settings owner,string label,Variant errors)
    {using var operations=new AudioDocumentOperations();using var args=new GArray{operations.validate_owner(owner,label)};EngineVariantDispatch.BuiltinCall(errors,"append_array",args);}
    public static void _validate_automation(Variant automation,string label,Variant errors)
    {using var operations=new AudioDocumentOperations();using var args=new GArray{operations.validate_automation(automation,label)};EngineVariantDispatch.BuiltinCall(errors,"append_array",args);}
    public ActorTimeline playback_model()=>(ActorTimeline)_operations.playback_model(this);
    public static KiwiAudioDocument from_source(Variant value,string label="")
    {using var operations=new AudioDocumentOperations();return (KiwiAudioDocument)operations.from_source(value,label);}
    public ActorClip? insert_source(Variant value,string track_id,double at)=>insert_source(value,track_id,at,"");
    public ActorClip? insert_source(Variant value,string track_id,double at,string label)=>_operations.insert_source(this,value,track_id,at,label) as ActorClip;
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_document").As<RefCounted>();
    public static KiwiAudioRecovery _new_recovery()=>new();
    public static RefCounted _native_recovery()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_recovery").As<RefCounted>();
    public static RefCounted _native_portable()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_portable").As<RefCounted>();
    public static string _recovery_kind(Resource resource)=>KiwiAudioRecovery._kind(resource);
    public static Resource? _new_recovery_resource(string kind)=>KiwiAudioRecovery._new_resource(kind);
    public static KiwiAudioPortableCopy _new_portable_scan()=>new();
    public static KiwiAudioPortableStage _new_portable_stage()=>new();
}
