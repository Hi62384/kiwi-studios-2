using Godot;

[GlobalClass]
public partial class KiwiImagePatternPreset : Resource
{
    [Export] public string label { get; set; } = "Pattern";
    [Export] public Texture2D? texture { get; set; }
    [Export] public Godot.Collections.Dictionary settings { get; set; } = new();
    [Export] public KiwiImageTextureRecipe? recipe { get; set; }
}
