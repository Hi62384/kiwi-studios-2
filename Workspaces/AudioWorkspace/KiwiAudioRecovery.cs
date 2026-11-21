using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioRecovery : RefCounted
{
    public const int FORMAT=1, MAX_METADATA=4*1024*1024, MAX_BLOB=256*1024*1024, MAX_STORE=512*1024*1024;
    public const int MAX_VISITS=100000, KEEP_PER_SESSION=3, KEEP_TOTAL=24;
    public const string MAGIC="KIWIREC1";
    private static readonly object StoreGate=new();
    private static Godot.Mutex? _mutex;
    private static Godot.Mutex StoreMutex {get {lock(StoreGate)return _mutex??=new();}}
    internal static void ClearResources() {lock(StoreGate){_mutex?.Dispose();_mutex=null;}}
    public string directory {get;set;}="user://audio_workspace/recovery_v1";
    public long metadata_limit {get;set;}=MAX_METADATA;
    public long blob_limit {get;set;}=MAX_BLOB;
    public long store_limit {get;set;}=MAX_STORE;
    public int keep_per_session {get;set;}=KEEP_PER_SESSION;
    public int keep_total {get;set;}=KEEP_TOTAL;
    public string _error {get;set;}="";
    public long _visits {get;set;}
    public long _estimated {get;set;}
    public GArray _nodes {get;set;}=new();
    public Settings _seen {get;set;}=new();
    public Settings _active {get;set;}=new();
    public Settings _blobs {get;set;}=new();
    public Settings _assets {get;set;}=new();
    public Settings _streams {get;set;}=new();
    public Settings _audio_cache {get;set;}=new();
    public RefCounted? _work {get;set;}
    public long _pending_bytes {get;set;}
    private readonly AudioRecoveryOperations _operations=new();
    public static Settings freeze(KiwiAudioDocument document)
    {using var operations=new AudioRecoveryOperations();return operations.freeze(document);}
    public Variant _freeze(Variant value,int depth)=>_operations.freeze_value(this,value,depth);
    public static bool _hex(string value,int length)
    {using var operations=new AudioRecoveryOperations();return operations.hex(value,length);}
    public string _root()=>_operations.root(this);
    public bool _cancelled()=>_operations.cancelled(this);
    public Variant _fail(string message)=>_operations.fail(this,message);
    public void _reset()=>_reset(null);
    public void _reset(RefCounted? work)=>_operations.reset(this,work);
    public static Godot.Collections.Array<string> _properties(Resource value)
    {using var operations=new AudioRecoveryOperations();return operations.properties(value);}
    public static string _kind(Resource? value)=>value switch
    {
        KiwiAudioDocument=>"document",ActorData=>"actor",ActorClip=>"clip",ActorAnimationTrack=>"animation",
        ActorKeyframe=>"key",ActorObjectData=>"object",ActorObjectReference=>"reference",Curve=>"curve",
        AudioStreamWav=>"wav",AudioStreamMP3=>"mp3",_=>""
    };
    public static Resource? _new_resource(string kind)=>kind switch
    {
        "document"=>new KiwiAudioDocument(),"actor"=>new ActorData(),"clip"=>new ActorClip(),
        "animation"=>new ActorAnimationTrack(),"key"=>new ActorKeyframe(),"object"=>new ActorObjectData(),
        "reference"=>new ActorObjectReference(),"curve"=>new Curve(),"wav"=>new AudioStreamWav(),"mp3"=>new AudioStreamMP3(),_=>null
    };
    public string _wav_blob(AudioStreamWav stream)=>_operations.wav_blob(this,stream);
    public Variant _encode(Variant value)=>_encode(value,0);
    public Variant _encode(Variant value,int depth)=>_operations.encode(this,value,depth);
    public Settings checkpoint(KiwiAudioDocument document,string session_id,long revision)=>checkpoint(document,session_id,revision,"",null);
    public Settings checkpoint(KiwiAudioDocument document,string session_id,long revision,string source_path)=>checkpoint(document,session_id,revision,source_path,null);
    public Settings checkpoint(KiwiAudioDocument document,string session_id,long revision,string source_path,RefCounted? work)=>_operations.checkpoint(this,StoreMutex,document,session_id,revision,source_path,work);
    public Settings _checkpoint(KiwiAudioDocument document,string session_id,long revision,string source_path,RefCounted? work)=>_operations.checkpoint_data(this,document,session_id,revision,source_path,work);
    public string _atomic_bytes(string destination,byte[] bytes)=>_operations.atomic_bytes(this,destination,bytes);
    public static long _file_size(string path)
    {using var operations=new AudioRecoveryOperations();return operations.file_size(path);}
    public long _used_bytes(string root)=>_operations.used_bytes(root);
    public Settings _read(string id)=>_operations.read(this,id);
    public Godot.Collections.Array<Settings> discover()=>_operations.discover(this,StoreMutex);
    public Godot.Collections.Array<Settings> _discover()=>_operations.discover_data(this);
    public void _prune(string newest)=>_operations.prune(this,newest);
    public Settings restore(string id)=>_operations.restore(this,StoreMutex,id);
    public Settings _restore(string id)=>_operations.restore_data(this,id);
    public bool _graph_value(Variant encoded,GArray nodes,Settings states,int depth)=>_operations.graph_value(this,encoded,nodes,states,depth);
    public Variant _decode(Variant encoded,Godot.Collections.Array<Resource> resources,int depth)
    {using var values=Variant.From(resources);return _operations.decode(this,encoded,values.AsGodotArray(),depth);}
    public long _packed_size(Variant value)
    {using var args=new GArray();return EngineVariantDispatch.BuiltinCall(value,"size",args).AsInt64();}
    public string _assign_recovery_field(Resource resource,string field,Variant value)
    {
        if (resource is ActorKeyframe && field=="value_curve" && value.VariantType!=Variant.Type.Nil && !(value.VariantType==Variant.Type.Object && value.AsGodotObject() is Curve)) return "Recovery animation curve type mismatch.";
        if (resource is ActorObjectReference && field=="embedded" && value.VariantType!=Variant.Type.Nil && !(value.VariantType==Variant.Type.Object && value.AsGodotObject() is ActorObjectData)) return "Recovery embedded object type mismatch.";
        var existing=resource.Get(field);
        using var args=new GArray();
        if (existing.VariantType==Variant.Type.Array && EngineVariantDispatch.BuiltinCall(existing,"is_typed",args).AsBool())
        {
            if (value.VariantType!=Variant.Type.Array) return "Invalid recovery array.";
            var source=existing.AsGodotArray();
            var typed=source.Duplicate();typed.Clear();
            int builtin=EngineVariantDispatch.BuiltinCall(existing,"get_typed_builtin",args).AsInt32();
            var script=EngineVariantDispatch.BuiltinCall(existing,"get_typed_script",args);
            foreach(var item in value.AsGodotArray())
            {
                if (builtin!=(int)item.VariantType) return "Recovery array element type mismatch.";
                if (item.VariantType==Variant.Type.Object && item.AsGodotObject() is Resource child && script.VariantType!=Variant.Type.Nil && !child.GetScript().Equals(script)) return "Recovery resource array type mismatch.";
                typed.Add(item);
            }
            value=typed;
        }
        else if (existing.VariantType!=Variant.Type.Nil && existing.VariantType!=value.VariantType) return "Recovery field type mismatch.";
        resource.Set(field,value);return "";
    }
}
