using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioAssetIndex : Node
{
    [Signal] public delegate void progress_changedEventHandler(string message);
    [Signal] public delegate void scan_finishedEventHandler(long generation,Settings result);
    public const int MAX_ROOTS=8,MAX_ASSETS=2048,MAX_DIRECTORIES=512,MAX_VISITED=20000,MAX_DEPTH=16;
    public const int MAX_SCAN_MSEC=15000,MAX_HEADER_BYTES=65536,MAX_TOTAL_HEADER_BYTES=16*1024*1024,MAX_PATH_CHARS=1024;
    public static readonly string[] EXTENSIONS={"wav","mp3","ogg","flac"},EXCLUDED={".godot",".git"};
    public long _generation {get;set;}
    public GodotThread? _thread {get;set;}
    public RefCounted? _work {get;set;}
    public long _running_generation {get;set;}
    public Settings _pending {get;set;}=new();
    public double _progress_elapsed {get;set;}
    private readonly AudioAssetIndexOperations _operations=new();
    public long request(Godot.Collections.Array<string> roots,Godot.Collections.Array<Settings> previous)
    {using var r=Variant.From(roots);using var p=Variant.From(previous);return _operations.request(this,r.AsGodotArray(),p.AsGodotArray());}
    public void cancel()=>_operations.cancel(this);
    public bool busy()=>_operations.busy(this);
    public override void _Process(double delta)=>_operations.process(this,delta);
    public override void _ExitTree()=>_operations.exit_tree(this);
    public override void _Notification(int what)
    {if(what==NotificationPredelete)_operations.exit_tree(this);}
    public static string canonical_root(string value)
    {using var operations=new AudioAssetIndexOperations();return operations.canonical_root(value);}
    public static bool contains_path(string root,string path)
    {using var operations=new AudioAssetIndexOperations();return operations.contains_path(root,path);}
    public static string path_state(string path,bool directory=false)
    {using var operations=new AudioAssetIndexOperations();return operations.path_state(path,directory);}
    public static bool usable(Settings entry)
    {using var operations=new AudioAssetIndexOperations();return operations.usable(entry);}
    public static string _root_for(string path,Godot.Collections.Array<string> roots)
    {using var operations=new AudioAssetIndexOperations();using var values=Variant.From(roots);return operations.root_for(path,values.AsGodotArray());}
    public static Settings _blank(string path,string root)
    {using var operations=new AudioAssetIndexOperations();return operations.blank(path,root);}
    public static string describe(Settings entry)
    {using var operations=new AudioAssetIndexOperations();return operations.describe(entry);}
    public static Settings _scan(Godot.Collections.Array<string> requested,Godot.Collections.Array<Settings> previous,RefCounted work)
    {using var operations=new AudioAssetIndexOperations();using var r=Variant.From(requested);using var p=Variant.From(previous);return operations.scan(r.AsGodotArray(),p.AsGodotArray(),work);}
    public static Settings _inspect(string path,string root,long budget)
    {using var operations=new AudioAssetIndexOperations();return operations.inspect(path,root,(int)budget);}
    public static bool _tag(byte[] bytes,long at,string value)
    {using var operations=new AudioAssetIndexOperations();return operations.tag(bytes,(int)at,value);}
    public static void _wav_metadata(byte[] bytes,long size,Settings entry)
    {using var operations=new AudioAssetIndexOperations();operations.wav_metadata(bytes,size,entry);}
    public static void _flac_metadata(byte[] bytes,Settings entry)
    {using var operations=new AudioAssetIndexOperations();operations.flac_metadata(bytes,entry);}
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_asset_index").As<RefCounted>();
}
