using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorAudio : RefCounted
{
    public const long MAX_CACHE_BYTES = 64L * 1024 * 1024, MAX_CACHE_SOURCES = 32,
        METADATA_INTERVAL_MSEC = 1000, MAX_IDLE_METADATA = 1024,
        MAX_NATIVE_WAV_BYTES = 64L * 1024 * 1024, MAX_FLAC_DISK_BYTES = 512L * 1024 * 1024,
        MAX_FLAC_FILE_BYTES = 128L * 1024 * 1024, MAX_FLAC_DISK_FILES = 256, MAX_FLAC_SCAN_ENTRIES = 4096;
    private static readonly object StateGate = new();
    private static Settings? _state;
    public static Settings _cache_state()
    {
        lock (StateGate)
        {
            return _state ??= new Settings
            {
                ["cache_mutex"] = new Godot.Mutex(), ["sources"] = new Settings(),
                ["metadata"] = new Settings(), ["identities"] = new Settings(), ["loads"] = new Settings(),
                ["generation"] = 0L, ["revision"] = 0L, ["use_serial"] = 0L, ["retained_bytes"] = 0L,
                ["flac_disk_mutex"] = new Godot.Mutex(), ["flac_used"] = new Settings(), ["flac_serial"] = 0L
            };
        }
    }
    public static Settings sources { get => _cache_state()["sources"].AsGodotDictionary(); set => _cache_state()["sources"] = value; }
    internal static void ClearCaches() { if (_state != null) new ActorAudioOperations().invalidate(_state, ""); }
    public static void invalidate(string path) => new ActorAudioOperations().invalidate(_cache_state(), path);
    public static void invalidate() => invalidate("");
    public static void _release_load(string path, Settings load) => new ActorAudioOperations().release_load(_cache_state(), path, load);
    public static void _retain_locked(string path, AudioStream stream) => new ActorAudioOperations().retain_locked(_cache_state(), path, stream);
    public static void _drop_strong_locked(string path) => new ActorAudioOperations().drop_strong_locked(_cache_state(), path);
    public static void _forget_locked(string path) => new ActorAudioOperations().forget_locked(_cache_state(), path);
    public static void _prune_metadata_locked(string protected_path) => new ActorAudioOperations().prune_metadata_locked(_cache_state(), protected_path);
    public static string _path_key(string path) => new ActorAudioOperations().path_key(path);
    public static Settings source_stamp(Variant value) => new ActorAudioOperations().source_stamp(_cache_state(), value);
    public static Settings _signature(string path) => new ActorAudioOperations().signature(path);
    public static Settings _file_metadata(string path) => _file_metadata(path, false);
    public static Settings _file_metadata(string path, bool force) => new ActorAudioOperations().file_metadata(_cache_state(), path, force);
    public static AudioStream? source(Variant value) => source(value, null);
    public static AudioStream? source(Variant value, RefCounted? job) => new ActorAudioOperations().source(_cache_state(), value, job);
    public static Settings pcm_info(string path) => new ActorAudioOperations().pcm_info(_cache_state(), path);
    public static double file_duration(Variant value) => file_duration(value, null);
    public static double file_duration(Variant value, RefCounted? job) => new ActorAudioOperations().file_duration(_cache_state(), value, job);
    public static bool needs_file_preview(Variant value) => new ActorAudioOperations().needs_file_preview(_cache_state(), value);
    public static AudioStream? _load_source(string path) => _load_source(path, null);
    public static AudioStream? _load_source(string path, RefCounted? job) => new ActorAudioOperations().load_source(_cache_state(), path, job);
    public static AudioStream? _load_flac(string path, Settings metadata) => _load_flac(path, metadata, null);
    public static AudioStream? _load_flac(string path, Settings metadata, RefCounted? job) => new ActorAudioOperations().load_flac(_cache_state(), path, metadata, job);
    public static long _flac_pcm_bytes(string path) => new ActorAudioOperations().flac_pcm_bytes(_cache_state(), path);
    public static AudioStream? _flac_disk_read(string decoded, string temporary, RefCounted? job) => new ActorAudioOperations().flac_disk_read(_cache_state(), decoded, temporary, job);
    public static bool _flac_disk_room(string protectedPath, long incomingBytes, bool isNew) => new ActorAudioOperations().flac_disk_room(_cache_state(), protectedPath, incomingBytes, isNew);
    public static AudioStream? _cached_locked(string path, string stamp) => new ActorAudioOperations().cached_locked(_cache_state(), path, stamp);
    public static long _retention_cost(AudioStream stream, long fileSize, string path) => new ActorAudioOperations().retention_cost(stream, fileSize, path);
    public static double length(ActorData actor) => new ActorAudioOperations().length(_cache_state(), actor);
    public static double fade_gain(ActorData actor, ActorClip clip, double time) => new ActorAudioOperations().fade_gain(actor, clip, time);
    public static bool valid(ActorData actor, ActorClip clip, double duration, double offset) => new ActorAudioOperations().valid(actor, clip, duration, offset);
}
