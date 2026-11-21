using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiLivePaintRegion : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string template_id { get; set; } = "";
    [Export] public Texture2D? coverage { get; set; } = null;
    [Export] public Texture2D? coordinates { get; set; } = null;
    [Export] public Rect2 coordinate_rect { get; set; } = new(0, 0, 1, 1);
    [Export] public Transform2D mapping { get; set; } = Transform2D.Identity;
    [Export] public Texture2D? raster { get; set; } = null;
    [Export] public double opacity { get; set; } = 1.0;
    private readonly ImageMaterialResourceOperations _operations = new();
    public KiwiLivePaintRegion copy_region() => (KiwiLivePaintRegion)_operations.copy_region(this);
    public bool is_live() => _operations.is_live(this);
}
