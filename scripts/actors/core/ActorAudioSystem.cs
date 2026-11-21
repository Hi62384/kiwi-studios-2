using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorAudioSystem : Node
{
    public Settings players { get; set; } = new();
    public Settings envelopes { get; set; } = new();
    public Settings jobs { get; set; } = new();
    public Settings _scrub_remaining { get; set; } = new();
    public string output_bus = "Master";
    public Settings clip_output_buses { get; set; } = new();
    public Settings clip_effects { get; set; } = new();
    public Settings clip_pan { get; set; } = new();
    public Settings clip_stream_overrides { get; set; } = new();
    public Settings _effect_signatures { get; set; } = new();
    private readonly ActorAudioSystemOperations _operations = new();
    public override Variant _Get(StringName property) => property == "output_bus" ? Variant.From(output_bus) : default;
    public override bool _Set(StringName property, Variant value)
    {
        if (property != "output_bus") return false;
        output_bus = value.AsString(); return true;
    }
    public void set_output_bus(string value) => _operations.set_output_bus(this, value);
    public void scrub(ActorTimeline model, double time) => _operations.scrub(this, model, time);
    public override void _Process(double delta) => _operations.process(this, delta);
    public void synchronize(ActorTimeline model, double time, bool playing) => _operations.synchronize(this, model, time, playing);
    public void _remove_player(string id) => _operations.remove_player(this, id);
    public float[] waveform(AudioStream? stream) => _operations.waveform(this, stream);
    public static float[] _decode(AudioStream stream) => new ActorAudioSystemOperations().decode(stream);
    public override void _ExitTree() => _operations.exit_tree(this);
}
