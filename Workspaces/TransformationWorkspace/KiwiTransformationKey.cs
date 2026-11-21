using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTransformationKey : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public double time { get; set; } = 0.0;
    [Export] public string state_id { get; set; } = "";
    [Export] public string mode { get; set; } = "Auto Morph";
    [Export] public long turns { get; set; } = 0;
    [Export] public Curve? curve { get; set; } = null;
    [Export] public Vector2[] points_a { get; set; } = Array.Empty<Vector2>();
    [Export] public Vector2[] points_b { get; set; } = Array.Empty<Vector2>();
    [Export] public Vector2[] reveal_path { get; set; } = Array.Empty<Vector2>();
    [Export] public double reveal_width { get; set; } = .3;
    [Export] public string alignment { get; set; } = "Bounds";
    [Export] public double preservation { get; set; } = .8;
    [Export] public string appearance { get; set; } = "Feature reveal";
    [Export] public string quality { get; set; } = "Fast";
    [Export] public string reveal_mode { get; set; } = "Point";
    [Export] public bool origin_enabled { get; set; } = false;
    [Export] public Vector2 morph_origin { get; set; } = new Vector2(.5f,.5f);
    [Export] public double direction { get; set; } = 90.0;
    [Export] public double topology_bias { get; set; } = 0.0;
    private readonly TransformationResourceOperations _operations = new();
    public static string[] modes() => new[] { "Auto Morph", "Shape Morph", "Guided Morph", "Grow / Reveal", "Step", "Crossfade" };
    public static string[] legacy_modes() => new[] { "Smooth morph", "Linear morph", "Reveal" };
    public Settings settings() => _operations.settings(this);
    public KiwiTransformationKey copy_key() => copy_key(false);
    public KiwiTransformationKey copy_key(bool new_identity) => (KiwiTransformationKey)_operations.copy_key(this, new_identity);
    public double progress(double value) => _operations.progress(this, value);

}
