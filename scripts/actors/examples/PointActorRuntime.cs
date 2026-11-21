using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class PointActorRuntime : ActorRuntime
{
    public Node3D? transform_node { get; set; }
    public Node3D? parenting_anchor { get; set; }
    private readonly PointActorOperations _operations = new();
    public override void _Ready()
    {
        transform_node = GetNode<Node3D>("Transform");
        _operations.ready(this);
    }
    public void refresh_model_binding(string path)
    {
        _operations.refresh_model_binding(this,path);
    }
    public override void set_active(bool value)
    {
        base.set_active(value);
        _operations.set_active(this,value);
    }
    public override Node parenting_node()
    {
        return _operations.parenting_node(this);
    }
    public override void evaluate_transform(Settings values)
    {
        _operations.evaluate_transform(this,values);
    }
    public override void evaluate(double _local_time, Settings _values)
    {
    }
    public override bool supports_remote_transform()
    {
        return true;
    }
    public override Transform3D remote_transform()
    {
        return _operations.remote_transform(this);
    }
    public override void apply_remote_transform(Transform3D source, bool use_position, bool use_rotation, bool use_scale)
    {
        _operations.apply_remote_transform(this,source,use_position,use_rotation,use_scale);
    }
}
