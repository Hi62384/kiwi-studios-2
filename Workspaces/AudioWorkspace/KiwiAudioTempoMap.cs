using Godot;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiAudioTempoMap : RefCounted
{
    public const int MAX_EVENTS = 4096, MAX_SOURCES = 128, MAX_MAP_COPIES = 65536,
        MAX_SOURCE_CHANNEL_EVENTS = 16384, MAX_TOTAL_CHANNEL_EVENTS = 131072,
        MAX_TOTAL_NOTES = 65536, MAX_SOURCE_NOTES = 8192;
    public const double MAX_BEAT = 10000000, MIN_SCALE = .000001, MAX_SCALE = 1000000;
    public Godot.Collections.Array<Settings> segments { get; set; } = new();
    public string error { get; set; } = "";
    private readonly AudioTempoMapOperations _operations = new();
    public KiwiAudioTempoMap() => _operations.initialize(this, new GArray(), 120, 1);
    public KiwiAudioTempoMap(GArray tempos, double bpm = 120, double timeScale = 1)
        => _operations.initialize(this, tempos, bpm, timeScale);
    public static KiwiAudioTempoMap create(Variant tempos, Variant bpm, Variant timeScale)
        => new(tempos.AsGodotArray(), bpm.AsDouble(), timeScale.AsDouble());
    public static Godot.Collections.Array<Settings> canonical(GArray tempos, double bpm = 120)
        => new AudioTempoMapOperations().canonical(tempos, bpm);
    public double beat_to_seconds(double beat) => _operations.beat_to_seconds(this, beat);
    public double seconds_to_beat(double seconds) => _operations.seconds_to_beat(this, seconds);
    public int _segment(double value, string field) => _operations.segment(this, value, field);
    public static Godot.Collections.Array<Settings> scaled_events(GArray tempos, double bpm, double timeScale = 1)
        => new AudioTempoMapOperations().scaled_events(tempos, bpm, timeScale);
    public static string validate_tempos(Variant value, bool allowEmpty = true) => new AudioTempoMapOperations().validate_tempos(value, allowEmpty);
    public static string validate_meters(Variant value) => new AudioTempoMapOperations().validate_meters(value);
    public static string validate_channel_events(Variant value) => new AudioTempoMapOperations().validate_channel_events(value);
    public static string validate_source(Settings owner) => new AudioTempoMapOperations().validate_source(owner);
    public static string validate_budget(GArray sources, Settings legacy) => new AudioTempoMapOperations().validate_budget(sources, legacy);
    public static bool _number_in(Variant value, double low, double high) => new AudioTempoMapOperations().number_in(value, low, high);
    public static bool _integer_in(Variant value, int low, int high) => new AudioTempoMapOperations().integer_in(value, low, high);
}
