using Godot;

[GlobalClass]
public partial class RigPreset : Resource
{
    [Export] public string title { get; set; } = "Custom rig";
    [Export] public Godot.Collections.Array<Godot.Collections.Dictionary> bones { get; set; } = new();
    [Export] public Godot.Collections.Dictionary metadata { get; set; } = new();
}
