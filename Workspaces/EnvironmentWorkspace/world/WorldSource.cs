using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class WorldSource : Resource
{
    [Export] public string world_id { get; set; } = ActorData.new_id();
    [Export] public long seed { get; set; } = 1;
    [Export] public Vector2 dimensions { get; set; } = new Vector2(256.0f,256.0f);
    [Export] public double region_size { get; set; } = 128.0;
    [Export] public string terrain_id { get; set; } = "";
    [Export] public string owned_terrain_id { get; set; } = "";
    [Export] public Godot.Collections.Array<Settings> regions { get; set; } = new();
    [Export] public Settings nodes { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> roads { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> settlements { get; set; } = new();
    [Export] public bool connect_settlements { get; set; } = true;
    [Export] public bool connection_bridges { get; set; } = true;
    [Export] public string connection_road_type { get; set; } = "Rural Road";
    [Export] public Settings connection_overrides { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> forests { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> prop_rules { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> exclusions { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> occupied { get; set; } = new();
    [Export] public bool respect_existing_objects { get; set; } = true;
    [Export] public bool auto_update_dependencies { get; set; } = true;
    [Export] public Settings plot_overrides { get; set; } = new();
    [Export] public double render_distance { get; set; } = 1000.0;
    [Export] public long max_building_plots { get; set; } = 4096;
    [Export] public long eager_building_limit { get; set; } = 128;
    [Export] public double building_detail_distance { get; set; } = 180.0;
    [Export] public long max_active_buildings { get; set; } = 64;
    [Export] public long building_cache_mb { get; set; } = 128;
    [Export] public Material? road_material { get; set; } = null;
    [Export] public Material? shoulder_material { get; set; } = null;
    [Export] public Settings road_materials { get; set; } = new();
    [Export] public long terrain_dependency_key { get; set; } = 0;
    public RefCounted? terrain_field { get; set; } = null;
    private readonly WorldSourceOperations _operations = new();
    public WorldSource copy() => (WorldSource)_operations.copy(this);
    public void configure_regions() => _operations.configure_regions(this);
    public string[] validate() => _operations.validate(this);
    public long signature() => _operations.signature(this);
    public long development_signature() => _operations.development_signature(this);
    public long geometry_signature() => _operations.geometry_signature(this);
    public string region_at(Vector2 point) => _operations.region_at(this, point);

}
