using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiPowderRuntime : BasicActorRuntime
{
    public MultiMeshInstance3D? grains { get; set; }
    public ShaderMaterial? grain_material { get; set; }
    public Godot.Collections.Array<MultiMeshInstance3D> batches { get; set; } = new();
    public long preview_key { get; set; } = -1;
    public long preview_updates { get; set; }
    public Settings visual_values { get; set; } = new();
    public Godot.Collections.Array<Mesh> geometry { get; set; } = new();
    public string material_warning { get; set; } = "";
    public long _appearance_key { get; set; } = -1;
    public long _identity_key { get; set; } = -1;
    public Settings identities { get; set; } = new();
    private readonly PowderRuntimeOperations _powderOperations = new();
    public override void _Ready() { content = new Node3D(); base._Ready(); _powderOperations.ready(this); }
    public void _add_batch() => _powderOperations.add_batch(this);
    public override void evaluate(double time, Settings values) { base.evaluate(time, values); _powderOperations.evaluate(this, time, values); }
    public override void _assign_material_override(Material? value) => _powderOperations.assign_material_override(this, value);
    public void clear_grains() => _powderOperations.clear_grains(this);
    public void show_state(Settings state) => _powderOperations.show_state(this, state);
    public int instance_count() => _powderOperations.instance_count(this);
}
