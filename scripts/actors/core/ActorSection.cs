using Godot;

[GlobalClass]
public partial class ActorSection : Resource
{
    [Export] public string id { get; set; } = "default";
    [Export] public string display_name { get; set; } = "Section 1";
}
