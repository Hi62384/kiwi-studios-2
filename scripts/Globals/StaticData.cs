using Godot;

[GlobalClass]
public partial class StaticData : Node
{
    private static Project? _loadedProject;
    public static Project? get_loaded_project() => GodotObject.IsInstanceValid(_loadedProject) ? _loadedProject : null;
    public static void set_loaded_project(Project? project) => _loadedProject = project;
}
