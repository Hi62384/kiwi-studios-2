using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiImageLayer : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string label { get; set; } = "Layer";
    [Export] public string kind { get; set; } = "paint";
    [Export] public string parent_id { get; set; } = "";
    [Export] public Vector2 position { get; set; } = Vector2.Zero;
    [Export] public Vector2 dimensions { get; set; } = new(400, 300);
    [Export] public double rotation { get; set; }
    [Export] public bool visible { get; set; } = true;
    [Export] public bool isolated { get; set; }
    [Export] public bool locked { get; set; }
    [Export] public double opacity { get; set; } = 1;
    [Export] public int blend { get; set; }
    [Export] public bool clip_to_below { get; set; }
    [Export] public Texture2D? texture { get; set; }
    [Export] public Texture2D? paint_base { get; set; }
    [Export] public Texture2D? mask { get; set; }
    [Export] public Godot.Collections.Array<Settings> effects { get; set; } = new();
    [Export] public Settings properties { get; set; } = new();
    [Export] public KiwiImageWarpData? warp { get; set; }
    [Export] public Godot.Collections.Array<KiwiLivePaintRegion> live_paint { get; set; } = new();
    private readonly ImageLayerOperations _operations = new();
    public static KiwiImageLayer create(string type, Vector2I canvas_size) => (KiwiImageLayer)new ImageLayerOperations().create(type, canvas_size);
    public static Vector2[] rounded_polygon(Vector2[] points, double radius) => new ImageLayerOperations().rounded_polygon(points, radius);
    public Transform2D local_transform() => _operations.local_transform(this);
    public Transform2D _orientation() => _operations.orientation(this);
    public Vector2 project_point(Vector2 point) => _operations.project_point(this, point, new Vector2(-1, -1));
    public Vector2 project_point(Vector2 point, Vector2 extent) => _operations.project_point(this, point, extent);
    public Vector2 unproject_point(Vector2 point) => _operations.unproject_point(this, point);
    public Rect2 projected_bounds() => _operations.projected_bounds(this, new Vector2(-1, -1));
    public Rect2 projected_bounds(Vector2 extent) => _operations.projected_bounds(this, extent);
    public void set_linear_basis(Transform2D basis) => _operations.set_linear_basis(this, basis);
    public Vector2 content_dimensions() => _operations.content_dimensions(this);
    public KiwiImageLayer copy_layer() => (KiwiImageLayer)_operations.copy_layer(this);
    public void erase_live_paint(Image? eraser) => _operations.erase_live_paint(this, eraser);
}
