using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiEnvironmentDocument : KiwiModelDocument
{
    [Export] public string environment_id { get; set; } = ActorData.new_id();
    [Export] public string title { get; set; } = "Untitled Environment";
    [Export] public Settings component_settings { get; set; } = new();
    [Export] public long random_seed { get; set; } = 1;
    [Export] public ActorObjectReference? atmosphere { get; set; }
    [Export] public string environment_source { get; set; } = "";
    [Export] public Settings sunlight { get; set; } = new() { ["enabled"] = true, ["rotation"] = new Vector3(-45, -30, 0), ["energy"] = 1.5, ["color"] = Colors.White };
    [Export] public EnvironmentClimate climate { get; set; } = new EnvironmentClimate();
    private readonly EnvironmentDocumentOperations _environment = new();
    public override string[] validate() => _environment.validate(this);
    public override KiwiModelDocument snapshot() => (KiwiModelDocument)_environment.snapshot(this);
    public Resource? terrain(string id) => _environment.terrain(this, id);
    public override string[] _component_geometry_errors(KiwiModelComponent item) => _environment.component_geometry_errors(this, item);
    public Settings water_at(Vector3 world_point) => _environment.water_at(this, world_point, Transform3D.Identity);
    public Settings water_at(Vector3 world_point, Transform3D environment_pose) => _environment.water_at(this, world_point, environment_pose);
    public string component_kind(string id) => _environment.component_kind(this, id);
    public bool references_asset(string path) => _environment.references_asset(this, path);
    public static bool _references(Variant value, string target, Settings seen) => new EnvironmentDocumentOperations().references(value, target, seen, 0);
    public static bool _references(Variant value, string target, Settings seen, int depth) => new EnvironmentDocumentOperations().references(value, target, seen, depth);
    public KiwiModelComponent add_terrain() => (KiwiModelComponent)_environment.add_terrain(this, null);
    public KiwiModelComponent add_terrain(Resource? settings) => (KiwiModelComponent)_environment.add_terrain(this, settings);
    public KiwiModelComponent add_group() => (KiwiModelComponent)_environment.add_group(this, "Group");
    public KiwiModelComponent add_group(string name) => (KiwiModelComponent)_environment.add_group(this, name);
}
