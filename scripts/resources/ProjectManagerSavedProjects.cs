using Godot;

[GlobalClass]
public partial class ProjectManagerSavedProjects : Resource
{
    [Export] public Godot.Collections.Array<string> project_paths { get; set; } = new();
}
