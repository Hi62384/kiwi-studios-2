using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class VideoActorRuntime : ActorRuntime
{
    public MeshInstance3D? mesh { get; set; }
    public Node3D? anchor { get; set; }
    public StandardMaterial3D? material { get; set; }
    public Texture2D? _last_texture { get; set; }
    public double _time { get; set; }
    public Settings _values { get; set; } = new();
    public string _path { get; set; } = "";
    private readonly VideoActorOperations _operations = new();
    public override void _Process(double _delta)
    {
        _operations.process(this,_delta);
    }
    public override void _Ready()
    {
        _operations.ready(this);
    }
    public override Node parenting_node()
    {
        return _operations.parenting_node(this);
    }
    public override void set_active(bool value)
    {
        base.set_active(value);
        _operations.set_active(this,value);
    }
    public override void evaluate_transform(Settings values)
    {
        _operations.evaluate_transform(this,values);
    }
    public override void evaluate(double time, Settings values)
    {
        _operations.evaluate(this,time,values);
    }
}
