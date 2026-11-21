using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class KiwiGrowthMaterial : Resource
{
    [Export] public string title { get; set; } = "Growth material";
    [Export] public string asset_id { get; set; } = ActorData.new_id();
    [Export] public string linked_source { get; set; } = "";
    [Export(PropertyHint.Enum, "Realistic,Stylized,Custom")] public long mode { get; set; } = 0;
    [Export] public Material? custom { get; set; } = null;
    [Export] public ActorObjectData? custom_asset { get; set; } = null;
    [Export] public Color root_color { get; set; } = new Color(.08f,.025f,.01f);
    [Export] public Color tip_color { get; set; } = new Color(.32f,.14f,.045f);
    [Export] public Color highlight_color { get; set; } = new Color(.9f,.8f,.65f);
    [Export] public double roughness { get; set; } = .5;
    [Export] public double specular { get; set; } = .55;
    [Export] public double secondary_highlight { get; set; } = .2;
    [Export] public double highlight_shift { get; set; } = .15;
    [Export] public double backlight { get; set; } = .15;
    [Export] public double opacity { get; set; } = 1.0;
    [Export(PropertyHint.Enum, "Cutout / automatic translucent hash,Alpha hash,Alpha to coverage (MSAA)")] public long coverage { get; set; } = 0;
    [Export] public Color emission { get; set; } = Colors.Black;
    [Export] public double variation { get; set; } = .12;
    [Export] public long bands { get; set; } = 3;
    [Export] public double edge_softness { get; set; } = .08;
    [Export] public double outline { get; set; } = 0.0;
    [Export] public Color outline_color { get; set; } = new Color(.015f,.01f,.02f);
    [Export] public Color shaft_color { get; set; } = new Color(.6f,.42f,.22f);
    [Export] public double feather_detail { get; set; } = .2;
    [Export] public double iridescence { get; set; } = 0.0;
    [Export(PropertyHint.Enum, "None,Bands,Spots,Edges,Tips,Speckles")] public long feather_pattern { get; set; } = 0;
    [Export] public Color feather_pattern_color { get; set; } = new Color(.08f,.04f,.015f);
    [Export] public double feather_pattern_scale { get; set; } = 5.0;
    [Export] public double feather_pattern_width { get; set; } = .2;
    [Export] public Color left_vane_color { get; set; } = Colors.White;
    [Export] public Color right_vane_color { get; set; } = Colors.White;
    [Export] public double shaft_roughness { get; set; } = .65;
    [Export(PropertyHint.Enum, "None,Stripes,Spots,Speckles,Mottle,Patches")] public long pattern { get; set; } = 0;
    [Export] public Color pattern_color { get; set; } = new Color(.015f,.01f,.005f);
    [Export] public double pattern_scale { get; set; } = 4.0;
    [Export] public double pattern_rotation { get; set; } = 0.0;
    [Export] public double pattern_mix { get; set; } = .7;
    [Export] public double pattern_seed { get; set; } = 31.0;
    [Export] public Texture2D? albedo_texture { get; set; } = null;
    [Export] public Texture2D? roughness_texture { get; set; } = null;
    [Export] public Texture2D? normal_texture { get; set; } = null;
    [Export] public Texture2D? alpha_texture { get; set; } = null;
    [Export] public Vector2 texture_scale { get; set; } = Vector2.One;
    [Export] public Vector2 texture_offset { get; set; } = Vector2.Zero;
    [Export] public double texture_rotation { get; set; } = 0.0;
    [Export] public Gradient? gradient { get; set; } = null;
    [Export] public Settings texture_sources { get; set; } = new();
    public ShaderMaterial? runtime { get; set; } = null;
    public long runtime_key { get; set; } = 0;
    public Settings texture_stamps { get; set; } = new();
    public Material? custom_runtime { get; set; } = null;
    public long custom_key { get; set; } = 0;
    public long custom_asset_key { get; set; } = 0;
    [ThreadStatic] private static GrowthMaterialOperations? _fallback;
    private static GrowthMaterialOperations Operations => Engine.HasSingleton("KiwiNativeServices")
        ? (GrowthMaterialOperations)((MigrationBootstrap)Engine.GetSingleton("KiwiNativeServices")).service("growth_material")
        : _fallback ??= new GrowthMaterialOperations();

    public static string[] presets() => new[] { "Black hair", "Warm hair", "Pale fur", "Striped coat", "Flight feathers", "Iridescent feathers", "Stylized ink" };
    public static KiwiGrowthMaterial preset(string name) => (KiwiGrowthMaterial)Operations.preset(name);
    public Texture2D thumbnail() => Operations.texture(null, this);
    public static long source_version(string path) => Operations.source_version(path);
    public static void invalidate_source(Variant source) => Operations.invalidate_source(source);
    public KiwiGrowthMaterial copy_material() => copy_material(false);
    public KiwiGrowthMaterial copy_material(bool unique) => (KiwiGrowthMaterial)Operations.copy_material(this, unique);
    public static GArray noise_signature(NoiseTexture2D texture) => Operations.noise_signature(texture);
    public long signature() => Operations.signature(this);
    public Material material() => Operations.material(this);
    public static Variant asset_values(Variant value) => Operations.asset_values(value, 0);
    public static Variant asset_values(Variant value, int depth) => Operations.asset_values(value, depth);
    public static Material? from_asset(Resource resource) => Operations.from_asset(resource);
    public Material prepare_custom() => Operations.prepare_custom(this);
}
