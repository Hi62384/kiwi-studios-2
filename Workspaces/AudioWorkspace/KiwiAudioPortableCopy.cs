using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioPortableCopy : RefCounted
{
    public const int FORMAT=1, CHUNK=65536, MAX_FILES=2048;
    public const long MAX_FILE_BYTES=512L*1024*1024, MAX_EXTERNAL_BYTES=2L*1024*1024*1024;
    public const long MAX_STREAM_BYTES=64L*1024*1024, MAX_EMBEDDED_BYTES=128L*1024*1024, MAX_DOCUMENT_BYTES=MAX_EMBEDDED_BYTES+16L*1024*1024;
    public const string TOKEN="kiwi-media://";
    public static readonly string[] MEDIA_KEYS={"audio","original_audio","sample","impulse","impulse_path"};
    public static readonly string[] EXTENSIONS={"wav","mp3","ogg","flac"};
    private static readonly object PublishGate=new();
    private static Godot.Mutex? _mutex;
    private static Godot.Mutex PublishMutex {get {lock(PublishGate)return _mutex??=new();}}
    internal static void ClearResources(){lock(PublishGate){_mutex?.Dispose();_mutex=null;}}
    public string _error {get;set;}="";
    public long _visits {get;set;}
    public Settings _seen {get;set;}=new();
    public Settings _active {get;set;}=new();
    public Godot.Collections.Array<Settings> _references {get;set;}=new();
    public Settings _streams {get;set;}=new();
    public long _embedded_bytes {get;set;}
    private readonly AudioPortableOperations _operations=new();
    public static Settings freeze(KiwiAudioDocument document)
    {using var operations=new AudioPortableOperations();return operations.freeze(document);}
    public static bool _cancelled(RefCounted? work)
    {using var operations=new AudioPortableOperations();return operations.is_cancelled(work);}
    public static string _canonical(string path)
    {using var operations=new AudioPortableOperations();return operations.canonical(path);}
    public static Settings _signature(string path)
    {using var operations=new AudioPortableOperations();return operations.signature(path);}
    public static Settings _hash_file(string path,Settings expected,RefCounted? work=null,string destination="")
    {using var operations=new AudioPortableOperations();return operations.hash_file(path,expected,work,destination);}
    public void _fail(string message)=>_operations.fail(this,message);
    public void _reference(Variant container,Variant key,Variant value,string label)=>_operations.reference(this,container,key,value,label);
    public void _walk(Variant value)=>_walk(value,"Composition",0);
    public void _walk(Variant value,string label)=>_walk(value,label,0);
    public void _walk(Variant value,string label,int depth)=>_operations.walk(this,value,label,depth);
    public static string _manifest_error(Settings manifest)
    {using var operations=new AudioPortableOperations();return operations.manifest_error(manifest);}
    public static Settings _manifest_map(Settings manifest)
    {using var operations=new AudioPortableOperations();return operations.manifest_map(manifest);}
    public static string _inside_state(string root,string relative)
    {using var operations=new AudioPortableOperations();return operations.inside_state(root,relative);}
    public static string _reference_id(string value,Settings entries,string root)
    {using var operations=new AudioPortableOperations();return operations.reference_id(value,entries,root);}
    public static string _infer_root(Godot.Collections.Array<Settings> references,Settings entries)
    {using var operations=new AudioPortableOperations();using var values=Variant.From(references);return operations.infer_root(values.AsGodotArray(),entries);}
    public static Settings resolve(KiwiAudioDocument document,string composition_path,bool allow_uncollected_sources=false)
    {using var operations=new AudioPortableOperations();return operations.resolve(document,composition_path,allow_uncollected_sources);}
    public static Settings for_save(KiwiAudioDocument document,string destination_path)
    {using var operations=new AudioPortableOperations();return operations.for_save(document,destination_path);}
    public static void _embed_streams(Godot.Collections.Array<Settings> references)
    {using var operations=new AudioPortableOperations();using var values=Variant.From(references);operations.embed_streams(values.AsGodotArray());}
    public static Settings inventory(KiwiAudioDocument document,string composition_path="",RefCounted? work=null)
    {using var operations=new AudioPortableOperations();return operations.inventory(document,composition_path,work);}
    public static Settings prepare(Settings review,string destination_folder,RefCounted? work=null)
    {using var operations=new AudioPortableOperations();return operations.prepare(review,destination_folder,work);}
    public static void discard(KiwiAudioPortableStage? stage)
    {using var operations=new AudioPortableOperations();operations.discard(stage);}
    public static Settings publish(KiwiAudioPortableStage? stage,RefCounted? work=null)
    {using var operations=new AudioPortableOperations();return operations.publish(stage,PublishMutex,work);}
    public static Settings _publish_ready(KiwiAudioPortableStage stage,RefCounted? work)
    {using var operations=new AudioPortableOperations();return operations.publish_ready(stage,work);}
    public static KiwiAudioPortableCopy _new_scan()=>new();
    public static KiwiAudioPortableStage _new_stage()=>new();
}
