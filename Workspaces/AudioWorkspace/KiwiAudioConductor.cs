using Godot;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiAudioConductor : RefCounted
{
    public const int MAX_POINTS = 1024;
    public const double MAX_BEAT = 10000000, MIN_GAP = .000001;
    public KiwiAudioTempoMap? timing { get; set; }
    public Godot.Collections.Array<Settings> meters { get; set; } = new();
    public string error { get; set; } = "";
    private readonly AudioConductorOperations _operations = new();
    public KiwiAudioConductor() => _operations.initialize(this, 120, new Vector2I(4, 4), new GArray(), new GArray());
    public KiwiAudioConductor(double bpm, Vector2I signature, GArray tempos, GArray signatures)
        => _operations.initialize(this, bpm, signature, tempos, signatures);
    public static KiwiAudioConductor create(Variant bpm, Variant signature, Variant tempos, Variant signatures)
        => new(bpm.AsDouble(), signature.AsVector2I(), tempos.AsGodotArray(), signatures.AsGodotArray());
    public static string validate(double bpm, Vector2I signature, Variant tempos, Variant signatures)
        => new AudioConductorOperations().validate(bpm, signature, tempos, signatures);
    public static bool _number(Variant value, double low, double high) => new AudioConductorOperations().number(value, low, high);
    public static bool _meter(Variant numerator, Variant denominator) => new AudioConductorOperations().meter(numerator, denominator);
    public double beat_to_seconds(double beat) => _operations.beat_to_seconds(this, beat);
    public double seconds_to_beat(double seconds) => _operations.seconds_to_beat(this, seconds);
    public double tempo_at(double seconds) => _operations.tempo_at(this, seconds);
    public Settings beat_info(double beat) => _operations.beat_info(this, beat);
    public string position_text(double seconds) => _operations.position_text(this, seconds);
    public double snap_seconds(double seconds, double step) => _operations.snap_seconds(this, seconds, step);
    public Godot.Collections.Array<Settings> grid(double first, double last, double pixelsPerSecond)
        => _operations.grid(this, first, last, pixelsPerSecond);
}
