using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTransformationComponent : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string title { get; set; } = "Component";
    [Export] public bool visible { get; set; } = true;
    [Export] public bool locked { get; set; } = false;
    [Export] public Vector2 base_size { get; set; } = new Vector2(1280,720);
    [Export] public string default_state_id { get; set; } = "";
    [Export] public Godot.Collections.Array<KiwiTransformationState> states { get; set; } = new();
    [Export] public Godot.Collections.Array<KiwiTransformationKey> keys { get; set; } = new();
    private readonly TransformationResourceOperations _operations = new();
    public KiwiTransformationState? state_for_id(string value) => _operations.lookup(this, "states", value) as KiwiTransformationState;
    public KiwiTransformationKey? key_for_id(string value) => _operations.lookup(this, "keys", value) as KiwiTransformationKey;
    public Godot.Collections.Array<KiwiTransformationKey> sorted_keys()
    {
        var result = new Godot.Collections.Array<KiwiTransformationKey>();
        foreach (var value in _operations.sorted_keys(this)) result.Add((KiwiTransformationKey)value.As<Resource>());
        return result;
    }
    public KiwiTransformationComponent copy_component() => copy_component(false);
    public KiwiTransformationComponent copy_component(bool new_identity) => (KiwiTransformationComponent)_operations.copy_component(this, new_identity);

}
