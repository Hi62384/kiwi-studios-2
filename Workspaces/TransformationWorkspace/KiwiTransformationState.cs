using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTransformationState : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string title { get; set; } = "State";
    [Export] public KiwiImageLayer? artwork { get; set; } = null;
    [Export] public Vector2 pivot { get; set; } = new Vector2(.5f,.5f);
    [Export] public long revision { get; set; } = 0;
    private readonly TransformationResourceOperations _operations = new();
    public KiwiTransformationState copy_state() => copy_state(false);
    public KiwiTransformationState copy_state(bool new_identity) => (KiwiTransformationState)_operations.copy_state(this, new_identity);
    public Vector2 anchor() => _operations.anchor(this);

}
