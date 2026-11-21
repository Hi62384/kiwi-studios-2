using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiAudioFilePreview : Node
{
    [Signal] public delegate void finishedEventHandler();
    [Signal] public delegate void failedEventHandler(string message);
    [Signal] public delegate void releasedEventHandler(string path);
    public const int CHUNK_FRAMES = 2048, MAX_BURSTS = 8, QUEUE_CHUNKS = 32, MAX_READERS = 3;
    public static int chunk_frames() => CHUNK_FRAMES;
    public static int queue_chunks() => QUEUE_CHUNKS;
    public AudioStreamPlayer player { get; set; } = new();
    public bool active { get; set; }
    private bool _loopEnabled;
    public bool loop_enabled
    {
        get => _loopEnabled;
        set
        {
            if (_loopEnabled == value) return;
            double position = position_seconds();
            _loopEnabled = value;
            if (active) seek_file(position);
        }
    }
    public double duration { get; set; }
    public Settings info { get; set; } = new();
    public RefCounted? _reader { get; set; }
    public Godot.Collections.Array<Settings> _readers { get; set; } = new();
    public AudioStreamGeneratorPlayback? _playback { get; set; }
    public int _capacity { get; set; }
    public long _origin { get; set; }
    public long _pushed { get; set; }
    public bool _eof { get; set; }
    public bool _priming { get; set; }
    public long _primed_at { get; set; }
    public long _generation { get; set; }
    public int _skips { get; set; }
    public string _last_error { get; set; } = "";
    public bool _held { get; set; }
    private readonly AudioFilePreviewOperations _operations = new();
    public override void _Ready() => AddChild(player);
    public string open_file(string path) => open_file(path, "Master", new Settings(), false, null, true);
    public string open_file(string path, string bus) => open_file(path, bus, new Settings(), false, null, true);
    public string open_file(string path, string bus, Settings prepared) => open_file(path, bus, prepared, false, null, true);
    public string open_file(string path, string bus, Settings prepared, bool owned) => open_file(path, bus, prepared, owned, null, true);
    public string open_file(string path, string bus, Settings prepared, bool owned, RefCounted? retainedOwner) => open_file(path, bus, prepared, owned, retainedOwner, true);
    public string open_file(string path, string bus, Settings prepared, bool owned, RefCounted? retainedOwner, bool autoStart)
        => _operations.open_file(this, path, bus, prepared, owned, retainedOwner, autoStart);
    public void seek_file(double seconds) => _operations.seek_file(this, seconds);
    public Settings prepared_token() => _operations.prepared_token(this);
    public bool is_primed() => is_primed(new Settings());
    public bool is_primed(Settings token) => _operations.is_primed(this, token);
    public string start_primed() => start_primed(new Settings());
    public string start_primed(Settings token) => _operations.start_primed(this, token);
    public double position_seconds() => _operations.position_seconds(this);
    public override void _Process(double delta) => _operations.process(this);
    public void _pump() => _operations.pump(this);
    public void close_file() => _operations.close_file(this);
    public void _reap_readers() => _reap_readers(false);
    public void _reap_readers(bool wait) => _operations.reap_readers(this, wait);
    public void _fail(string message) => _operations.fail(this, message);
    public override void _ExitTree() => _operations.exit_tree(this);
}
