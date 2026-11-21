using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTextureMaterial : Resource
{
    [Export] public string material_id { get; set; } = "wood/oak";
    [Export] public int format_version { get; set; } = 2;
    [Export] public string label { get; set; } = "Oak";
    [Export] public Settings parameters { get; set; } = new();
    [Export] public Texture2D? image { get; set; } = null;
    [Export] public double texture_size { get; set; } = 64.0;
    [Export] public double rotation { get; set; } = 0.0;
    [Export] public string alignment { get; set; } = "layer";
    [Export] public string application { get; set; } = "continuous";
    [Export] public double spacing { get; set; } = .8;
    [Export] public double jitter { get; set; } = .25;
    [Export] public double random_rotation { get; set; } = 0.0;
    [Export] public double random_scale { get; set; } = 0.0;
    [Export] public bool follow_direction { get; set; } = false;
    [Export] public double direction_smoothing { get; set; } = .7;
    [Export] public Vector2 mapping_origin { get; set; } = Vector2.Zero;
    [Export] public double tint_strength { get; set; } = 0.0;
    [Export] public string tiling { get; set; } = "repeat";
    [Export] public string blending { get; set; } = "replace";
    [Export] public KiwiTextureMaterial? secondary { get; set; } = null;
    [Export] public double mix_amount { get; set; } = 0.0;
    [Export] public string mix_distribution { get; set; } = "noise";
    [Export] public Texture2D? mix_mask { get; set; } = null;
    [Export] public double relief { get; set; } = 0.0;
    [Export] public double relief_softness { get; set; } = .3;
    [Export] public double light_direction { get; set; } = 45.0;
    [Export] public double highlight { get; set; } = 1.0;
    [Export] public double shadow { get; set; } = 1.0;
    [Export] public Texture2D? coverage { get; set; } = null;
    [Export] public Texture2D? source { get; set; } = null;
    [Export] public string surface_mapping { get; set; } = "uv";
    [Export] public double triplanar_sharpness { get; set; } = 4.0;
    [Export] public double metallic { get; set; } = -1.0;
    private readonly ImageMaterialResourceOperations _operations = new();
    public KiwiTextureMaterial copy_material() => (KiwiTextureMaterial)_operations.copy_material(this);
}
