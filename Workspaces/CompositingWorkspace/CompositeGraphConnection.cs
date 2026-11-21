using Godot;

public partial class CompositeGraphConnection : Resource
{
    [Export] public string from_node { get; set; } = "";
    [Export] public string from_port { get; set; } = "";
    [Export] public string to_node { get; set; } = "";
    [Export] public string to_port { get; set; } = "";
}
