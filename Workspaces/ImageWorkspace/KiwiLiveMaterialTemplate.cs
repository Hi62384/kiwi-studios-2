using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiLiveMaterialTemplate : Resource
{
    [Export] public int version { get; set; } = 1;
    [Export] public string id { get; set; } = "";
    [Export] public string label { get; set; } = "Natural Material";
    [Export] public KiwiTextureMaterial? material { get; set; } = null;
    [Export] public bool visible { get; set; } = true;
    private readonly ImageMaterialResourceOperations _operations = new();
    public KiwiLiveMaterialTemplate copy_template() => (KiwiLiveMaterialTemplate)_operations.copy_template(this);
}
