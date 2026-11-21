using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiImageTextureRecipe : Resource
{
    [Export] public string kind { get; set; } = "fractal";
    [Export] public Settings settings { get; set; } = new()
    {
        ["frequency"] = .035, ["scale"] = 1.0, ["contrast"] = 1.0, ["brightness"] = 0.0,
        ["density"] = .5, ["roughness"] = .5, ["octaves"] = 4, ["rotation"] = 0.0,
        ["seed"] = 0, ["seamless"] = true, ["invert"] = false,
        ["primary"] = new Color(.15f, .2f, .25f), ["secondary"] = new Color(.85f, .9f, .95f)
    };
    [Export] public ActorObjectData? noise_object { get; set; }
    private readonly ImageProceduralTextureOperations _operations = new();
    public KiwiImageTextureRecipe copy_recipe() => (KiwiImageTextureRecipe)_operations.copy_recipe(this);
    public FastNoiseLite configure_noise() => _operations.configure_noise(this);
}
