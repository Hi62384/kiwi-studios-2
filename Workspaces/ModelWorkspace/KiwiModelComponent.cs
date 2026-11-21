using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiModelComponent : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string title { get; set; } = "Component";
    [Export] public string parent_id { get; set; } = "";
    [Export] public Transform3D transform { get; set; } = Transform3D.Identity;
    [Export] public Vector3 pivot { get; set; } = Vector3.Zero;
    [Export] public KiwiModelMesh? mesh { get; set; }
    [Export] public string generator { get; set; } = "";
    [Export] public Settings parameters { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> modifiers { get; set; } = new();
    [Export] public Godot.Collections.Array<Material> surface_materials { get; set; } = new();
    [Export] public bool visible { get; set; } = true;
    [Export] public bool locked { get; set; }
    [Export] public bool is_skeleton { get; set; }
    [Export] public Godot.Collections.Array<Settings> bones { get; set; } = new();
    [Export] public Skin? skin { get; set; }
    [Export] public Mesh? skin_mesh { get; set; }
    [Export] public string skeleton_id { get; set; } = "";
    [Export] public KiwiRigBinding? binding { get; set; }
    [Export] public Mesh? geometry_source { get; set; }
    [Export] public long geometry_source_hash { get; set; }
    [Export] public Settings structural { get; set; } = new();
    [Export] public KiwiSurfaceGrowthData? growth { get; set; }
    private readonly ModelComponentOperations _operations = new();
    public ArrayMesh render_mesh() => _operations.render_mesh(this, default);
    public ArrayMesh render_mesh(Variant material_scope) => _operations.render_mesh(this, material_scope);
    public KiwiModelComponent copy_component() => copy_component(false);
    public KiwiModelComponent copy_component(bool new_identity) => (KiwiModelComponent)_operations.copy_component(this, new_identity);
}
