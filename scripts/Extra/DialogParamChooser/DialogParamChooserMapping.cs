using Godot;

[GlobalClass]
public partial class DialogParamChooserMapping : Resource
{
    [Export] public NodePath node { get; set; } = new("");
    [Export] public string property_name { get; set; } = "";
    [Export] public string tag { get; set; } = "";
}
