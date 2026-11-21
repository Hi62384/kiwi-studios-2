using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class BuildingSource : Resource
{
    [Export] public string source_id { get; set; } = ActorData.new_id();
    [Export] public string title { get; set; } = "Building";
    [Export] public long seed { get; set; } = 1;
    [Export] public Vector2[] footprint { get; set; } = Array.Empty<Vector2>();
    [Export] public Godot.Collections.Array<Settings> floors { get; set; } = new();
    [Export] public double wall_thickness { get; set; } = .2;
    [Export] public double slab_thickness { get; set; } = .15;
    [Export(PropertyHint.Enum, "Flat,Gable,Shed,Hip")] public long roof_type { get; set; } = 1;
    [Export] public double roof_pitch { get; set; } = 30.0;
    [Export] public double roof_overhang { get; set; } = .25;
    [Export] public Godot.Collections.Array<Material> materials { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> stairs { get; set; } = new();
    [Export] public bool physics_enabled { get; set; } = false;
    [Export] public double foundation_depth { get; set; } = .4;
    [Export] public string style { get; set; } = "Custom";
    [Export(PropertyHint.Enum, "None,Timber frame,Porch,Buttresses,Pilasters,Fins,Cross braces,Spire corners")] public long facade_detail { get; set; } = 0;
    [Export] public double detail_width { get; set; } = .12;
    [Export] public double baseboard_height { get; set; } = 0.0;
    [Export] public double crown_height { get; set; } = 0.0;
    [Export] public double interior_trim_depth { get; set; } = .025;
    private readonly BuildingSourceOperations _operations = new();
    public static BuildingSource copy(Resource authored) => (BuildingSource)new BuildingSourceOperations().copy(authored);
    public static BuildingSource rectangular() => rectangular(6, 8, 1, true);
    public static BuildingSource rectangular(double width) => rectangular(width, 8, 1, true);
    public static BuildingSource rectangular(double width, double depth) => rectangular(width, depth, 1, true);
    public static BuildingSource rectangular(double width, double depth, int levels) => rectangular(width, depth, levels, true);
    public static BuildingSource rectangular(double width, double depth, int levels, bool with_materials) => (BuildingSource)new BuildingSourceOperations().rectangular(width, depth, levels, with_materials);
    public string[] validate() => _operations.validate(this);
    public static double wall_height(Resource source, Settings floor, Settings wall) => new BuildingSourceOperations().wall_height(source, floor, wall);

}
