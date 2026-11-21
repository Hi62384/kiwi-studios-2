using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiAudioSourceCache : Node
{
    [Signal] public delegate void waveform_readyEventHandler(string key);
    public const int MAX_CACHE_BYTES = 48 * 1024 * 1024, MAX_WORKERS = 2, MAX_DECODE_BYTES = 128 * 1024 * 1024;
    public Settings entries { get; set; } = new();
    public Settings _jobs { get; set; } = new();
    public Settings _pending { get; set; } = new();
    public long _generation { get; set; }
    private readonly AudioSourceCacheOperations _operations = new();
    public static string identity(AudioStream? stream) => new AudioSourceCacheOperations().identity(stream);
    public static Settings decode(AudioStream? stream, int rate = 44100, double start = 0, double duration = -1, double limitSeconds = 300)
        => new AudioSourceCacheOperations().decode(stream, rate, start, duration, limitSeconds);
    public static AudioStreamWav to_wav(Vector2[] samples, int rate = 44100, bool stereo = true)
        => new AudioSourceCacheOperations().to_wav(samples, rate, stereo);
    public Settings request(AudioStream? stream) => _operations.request(this, stream);
    public Settings request_source(Variant value) => _operations.request_source(this, value);
    public Settings _request_value(Variant value, string key) => _operations.request_value(this, value, key);
    public void invalidate() => invalidate(null);
    public void invalidate(AudioStream? stream) => _operations.invalidate(this, stream);
    public override void _Process(double delta) => _operations.process(this);
    public static Settings _build_source_envelope(Variant value, string key, RefCounted token) => new AudioSourceCacheOperations().build_source_envelope(value, key, token);
    public void _evict() => _operations.evict(this);
    public static Settings build_envelope(AudioStream? stream, RefCounted? token = null) => new AudioSourceCacheOperations().build_envelope(stream, token);
    public static Settings build_file_envelope(string path, Settings info, RefCounted? token = null) => new AudioSourceCacheOperations().build_file_envelope(path, info, token);
    public static Settings _envelope_levels(Vector2[] left, Vector2[] right, long stride, int rate, double seconds) => new AudioSourceCacheOperations().envelope_levels(left, right, stride, rate, seconds);
    public static Vector2[] range_peaks(Settings entry, double start, double duration, int pixels, int channel = 0) => new AudioSourceCacheOperations().range_peaks(entry, start, duration, pixels, channel);
    public override void _ExitTree() => _operations.exit_tree(this);
    public static AudioStreamWav? fit_pattern(AudioStreamWav stream, double seconds) => new AudioSourceCacheOperations().fit_pattern(stream, seconds);
    public RefCounted _new_work() => new AudioWorkToken();
}
