using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class Project : Resource
{
    [Export] public string project_name { get; set; } = "";
    [Export] public ActorInspectorState actor_inspector_state { get; set; } = new();
    [Export] public Settings fog_rendering { get; set; } = new();
    public Project() { }
    public Project(string name) { project_name = name; }
    public static Project create(string name) => new(name);
}
