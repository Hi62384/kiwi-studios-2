using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioPreset : Resource
{
    [Export] public int version {get;set;}=1;
    [Export] public string id {get;set;}="";
    [Export] public string label {get;set;}="Preset";
    [Export] public string kind {get;set;}="generator";
    [Export] public string[] tags {get;set;}=System.Array.Empty<string>();
    [Export] public string folder {get;set;}="";
    [Export] public Settings data {get;set;}=new();
    [Export] public KiwiAudioDocument? composition {get;set;}
    public const int MAX_JSON_BYTES=1024*1024,MAX_PATTERN_NOTES=8192;
    public static Settings pattern_data(ActorData actor,KiwiAudioDocument? document=null)
    {using var operations=new AudioPresetOperations();return operations.pattern_data(actor,document);}
    public static string apply_pattern(KiwiAudioEditSession session,KiwiAudioPreset preset,double at=0,string track_id="",bool create_clip=false)
    {using var operations=new AudioPresetOperations();return operations.apply_pattern(session,preset,at,track_id,create_clip);}
    public static string validate_pattern(Settings value)
    {using var operations=new AudioPresetOperations();return operations.validate_pattern(value);}
    public static bool _number_in(Variant value,double low,double high)
    {using var operations=new AudioPresetOperations();return operations.number_in(value,low,high);}
    public static bool _data_only(Variant value,long depth=0,GArray? budget=null)
    {using var operations=new AudioPresetOperations();return operations.data_only(value,(int)depth,budget??new GArray{0});}
    public static Settings to_json_text(KiwiAudioPreset preset)
    {using var operations=new AudioPresetOperations();return operations.to_json_text(preset);}
    public static Settings from_json_text(string text)
    {using var operations=new AudioPresetOperations();return operations.from_json_text(text);}
    public static Settings import_pattern_json(string path)
    {using var operations=new AudioPresetOperations();return operations.import_pattern_json(path);}
    public static string export_pattern_json(string path,KiwiAudioPreset preset)
    {using var operations=new AudioPresetOperations();return operations.export_pattern_json(path,preset);}
    public static bool _json_audio_paths(Variant value)
    {using var operations=new AudioPresetOperations();return operations.json_audio_paths(value);}
    public static bool _json_depth_allowed(string text)
    {using var operations=new AudioPresetOperations();return operations.json_depth_allowed(text);}
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_preset").As<RefCounted>();
}
