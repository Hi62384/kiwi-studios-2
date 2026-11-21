using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class KiwiPhysicsBakeCache : Resource
{
    public const int CHUNK_FRAMES = 32;
    public const long MAX_BYTES = 67108864, MAX_RAW_BYTES = 268435456, MAX_STREAM_BYTES = 4294967296, MAX_CHUNK_RAW = 16777216;
    [Export] public Godot.Collections.Array<Resource> resources { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> records { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> chunks { get; set; } = new();
    [Export] public long count { get; set; }
    [Export] public long bytes { get; set; }
    [Export] public long raw_bytes { get; set; }
    [Export] public long resource_bytes { get; set; }
    [Export] public string storage_root { get; set; } = "";
    [Export] public bool complete { get; set; }
    public string error { get; set; } = "";
    public Godot.Collections.Array<string> owned_files { get; set; } = new();
    public GArray pending { get; set; } = new();
    public long pending_bytes { get; set; }
    public Settings resource_indices { get; set; } = new();
    public Settings record_indices { get; set; } = new();
    public Settings decoded { get; set; } = new();
    private readonly PhysicsBakeCacheOperations _operations = new();
    public string begin_stream(string directory) => _operations.begin_stream(this, directory);
    public static string digest(byte[] data) => new PhysicsBakeCacheOperations().digest(data);
    public Variant encode(Variant value) => _operations.encode(this, value, "");
    public Variant encode(Variant value, string key) => _operations.encode(this, value, key);
    public Variant decode(Variant value) => _operations.decode(this, value);
    public string append(Settings frame) => _operations.append(this, frame);
    public string flush() => _operations.flush(this);
    public string finish_stream() => _operations.finish_stream(this);
    public void abort_stream() => _operations.abort_stream(this);
    public byte[] packed_chunk(Settings chunk) => _operations.packed_chunk(this, chunk);
    public Settings frame(int index) => _operations.frame(this, index);
}
