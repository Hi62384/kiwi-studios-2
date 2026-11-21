using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorAnimationTrack : Resource
{
    [Export] public string[] path { get; set; } = Array.Empty<string>();
    [Export] public string label { get; set; } = "";
    [Export] public Godot.Collections.Array<ActorKeyframe> keys { get; set; } = new();
    [Export] public int component { get; set; } = -1;
    [Export] public Variant component_base { get; set; }
    private readonly ActorAnimationTrackOperations _operations = new();
    public void sort_keys() => _operations.sort_keys(this);
    public ActorKeyframe? key_at(double time) => _operations.key_at(this, time) as ActorKeyframe;
    public Variant sample(double time) => _operations.sample(this, time, default);
    public Variant sample(double time, Variant fallback) => _operations.sample(this, time, fallback);
    public bool is_state_track() => _operations.is_state_track(this);
    public Settings transition_at(double time) => _operations.transition_at(this, time, default);
    public Settings transition_at(double time, Variant fallback) => _operations.transition_at(this, time, fallback);
    public static string interpolate_text(string left, string right, double weight) => new ActorAnimationTrackOperations().interpolate_text(left, right, weight);
    public ActorAnimationTrack copy_track() => (ActorAnimationTrack)_operations.copy_track(this);
}
