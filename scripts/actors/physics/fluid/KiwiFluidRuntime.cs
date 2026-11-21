using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiFluidRuntime : BasicActorRuntime
{
    public MeshInstance3D? surface { get; set; }
    public ShaderMaterial? liquid_material { get; set; }
    public long surface_key { get; set; } = -1;
    public Settings surface_stats { get; set; } = new();
    private readonly FluidRuntimeOperations _fluidOperations = new();
    public override void _Ready() { content = new Node3D(); base._Ready(); _fluidOperations.ready(this); }
    public override void evaluate(double time, Settings values) { base.evaluate(time, values); _fluidOperations.evaluate(this, time, values); }
    public void show_state(Settings state, Settings values) => _fluidOperations.show_state(this, state, values);
    public void clear_surface() => _fluidOperations.clear_surface(this);
}
