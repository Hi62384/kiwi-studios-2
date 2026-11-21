using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class KiwiAudioPlayback : Node
{
    [Signal] public delegate void position_changedEventHandler(double seconds);
    [Signal] public delegate void state_changedEventHandler();
    [Signal] public delegate void exact_requestedEventHandler(double seconds);
    [Signal] public delegate void preview_file_releasedEventHandler(string path);
    [Signal] public delegate void preview_failedEventHandler(string message);
    public ActorAudioSystem system { get; set; } = new();
    public Resource? document;
    public ActorTimeline model { get; set; } = new();
    public double position { get; set; }
    public bool playing { get; set; }
    public bool metronome { get; set; }
    public bool loop_enabled { get; set; }
    public Godot.Collections.Array<string> _bus_names { get; set; } = new();
    public Settings _track_buses { get; set; } = new();
    public Settings _track_effects { get; set; } = new();
    public string _master { get; set; } = "";
    public AudioStreamPlayer _click { get; set; } = new();
    public string _last_beat { get; set; } = "";
    public KiwiAudioConductor _conductor { get; set; } = new();
    public string _external_output { get; set; } = "Master";
    public string _bus_signature { get; set; } = "";
    public Godot.Collections.Array<ActorData> _runtime_sources { get; set; } = new();
    public AudioStreamPlayer exact_preview { get; set; } = new();
    public bool exact_preview_active { get; set; }
    public double _exact_start { get; set; }
    public bool exact_required { get; set; }
    public bool exact_pending { get; set; }
    public string _exact_bus { get; set; } = "";
    public KiwiAudioFilePreview file_preview { get; set; } = new();
    public double _file_length { get; set; }
    public Settings _recording_file_token { get; set; } = new();
    public WeakRef? _recording_file_owner { get; set; }
    public Settings rendered_route_meters { get; set; } = new();
    public double rendered_meter_start { get; set; }
    public int rendered_meter_hz { get; set; } = 20;
    private readonly AudioPlaybackOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public override Variant _Get(StringName property) => property == "document" ? Variant.From(document) : default;
    public override bool _Set(StringName property, Variant value)
    {
        if (property != "document") return false;
        document = value.VariantType == Variant.Type.Object ? value.As<Resource>() : null; return true;
    }
    public void set_document(Resource? value) => _operations.set_document(this, value);
    public void set_output_bus(string destination) => _operations.set_output_bus(this, destination);
    public string _new_bus(string label, string destination) => _operations.new_bus(this, label, destination);
    public void _rebuild_buses() => _operations.rebuild_buses(this);
    public void _install_effects(int bus, GArray stack) => _operations.install_effects(bus, stack);
    public void _clear_buses() => _operations.clear_buses(this);
    public void play() => _operations.play(this);
    public void stop() => stop(true);
    public void stop(bool reset) => _operations.stop(this, reset);
    public void seek(double seconds) => seek(seconds, false);
    public void seek(double seconds, bool scrub) => _operations.seek(this, seconds, scrub);
    public void play_exact(AudioStream stream, double start) => _operations.play_exact(this, stream, start);
    public string play_file(string path, double start, Settings info) => _operations.play_file(this, path, start, info);
    public string prepare_recording_file(string path, double start, Settings info, RefCounted owner) => _operations.prepare_recording_file(this, path, start, info, owner);
    public bool recording_file_ready(RefCounted owner) => _operations.recording_file_ready(this, owner);
    public string start_recording_file(RefCounted owner) => _operations.start_recording_file(this, owner);
    public override void _Process(double delta) => _operations.process(this, delta);
    public string musical_position(double seconds) => _operations.musical_position(this, seconds);
    public void synchronize() => _operations.synchronize(this);
    public bool meter_supported() => meter_supported("");
    public bool meter_supported(string trackId) => _operations.meter_supported(this, trackId);
    public Vector2 meter() => meter("");
    public Vector2 meter(string trackId) => _operations.meter(this, trackId);
    public override void _ExitTree() => _operations.exit_tree(this);
    public void _update_effects(int bus, GArray stack) => _operations.update_effects(this, bus, stack);
}
