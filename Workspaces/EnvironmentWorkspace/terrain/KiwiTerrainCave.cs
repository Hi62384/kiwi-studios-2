using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTerrainCave : Resource
{
    [Export] public string cave_id { get; set; } = ActorData.new_id();
    [Export] public string title { get; set; } = "Cave";
    [Export] public bool enabled { get; set; } = true;
    [Export] public long seed { get; set; } = 1;
    [Export] public double radius { get; set; } = 2.0;
    [Export] public double radius_variation { get; set; } = .15;
    [Export] public double junction_smoothing { get; set; } = .4;
    [Export] public double roughness { get; set; } = .15;
    [Export] public double detail_frequency { get; set; } = .7;
    [Export] public Godot.Collections.Array<Vector3[]> paths { get; set; } = new();
    [Export] public Vector4[] chambers { get; set; } = Array.Empty<Vector4>();
    [Export] public Godot.Collections.Array<Settings> edits { get; set; } = new();
    public FastNoiseLite? _noise { get; set; } = null;
    private readonly TerrainCaveOperations _operations = new();
    public long signature() => _operations.signature(this);
    public string[] validate() => _operations.validate(this);
    public void prepare() => _operations.prepare(this);
    public double segment_radius(int index) => _operations.segment_radius(this, index);
    public Aabb bounds() => _operations.bounds(this);
    public double distance(Vector3 point) => _operations.distance(this, point);
    public double _raw_distance(Vector3 point) => _operations.raw_distance(this, point);
    public long local_signature(Aabb region) => _operations.local_signature(this, region);
    public static double _smooth_min(double a, double b, double width) => new TerrainCaveOperations().smooth_min(a, b, width);
    public static KiwiTerrainCave network(Vector3 entrance) => network(entrance, 6, 16, 2, 1);
    public static KiwiTerrainCave network(Vector3 entrance, double depth) => network(entrance, depth, 16, 2, 1);
    public static KiwiTerrainCave network(Vector3 entrance, double depth, double length) => network(entrance, depth, length, 2, 1);
    public static KiwiTerrainCave network(Vector3 entrance, double depth, double length, int branches) => network(entrance, depth, length, branches, 1);
    public static KiwiTerrainCave network(Vector3 entrance, double depth, double length, int branches, long seed) => (KiwiTerrainCave)new TerrainCaveOperations().network(entrance, depth, length, branches, seed);

}
