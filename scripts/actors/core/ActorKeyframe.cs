using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorKeyframe : Resource
{
    public enum Interpolation { LINEAR, EASE, STEP }
    [Export] public string id { get; set; } = "";
    [Export] public double time { get; set; }
    [Export] public Variant value { get; set; }
    [Export] public Interpolation interpolation { get; set; } = Interpolation.LINEAR;
    [Export] public double attenuation { get; set; } = 1.0;
    [Export] public Curve? value_curve { get; set; }
    [Export] public string curve_template { get; set; } = "Linear";
    [Export] public double curve_adjustment { get; set; }
    public ActorKeyframe copy_key() => (ActorKeyframe)new ActorAnimationTrackOperations().copy_key(this);
    public static Settings interpolation_modes() => new() { ["LINEAR"] = (int)Interpolation.LINEAR, ["EASE"] = (int)Interpolation.EASE, ["STEP"] = (int)Interpolation.STEP };
}
