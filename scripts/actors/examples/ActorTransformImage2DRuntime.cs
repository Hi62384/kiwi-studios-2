using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorTransformImage2DRuntime : ActorUIRuntime
{
    // These remaining transformation workspace state bridges are tracked separately.
    public Node renderer { get; set; } = GD.Load<GDScript>("res://Workspaces/TransformationWorkspace/transformation_renderer.gd").New().As<Node>();
    public RefCounted session { get; set; } = GD.Load<GDScript>("res://Workspaces/TransformationWorkspace/transformation_session.gd").New().As<RefCounted>();
    public ShaderMaterial premultiplied { get; set; } = new();
    private readonly TransformImageActorOperations _transformOperations = new();
    public override void _Ready() { base._Ready(); _transformOperations.ready(this); }
    public override void set_active(bool value) { base.set_active(value); _transformOperations.set_active(this, value); }
    public override void evaluate_transform(Settings values) { base.evaluate_transform(values); _transformOperations.evaluate_transform(this, values); }
    public override void evaluate(double time, Settings values) { base.evaluate(time, values); _transformOperations.evaluate(this, time, values); }
}
