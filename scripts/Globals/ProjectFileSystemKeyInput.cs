using Godot;

[GlobalClass]
public partial class ProjectFileSystemKeyInput : FocusableKeyInput
{
    public Node? file_system_extra_ui { get; set; }
    public Node? file_system_callable_actions { get; set; }
    private readonly ProjectFileInputOperations _operations = new();
    public override void _Ready()
    {
        file_system_extra_ui = GetNode<Node>("../FileSystemExtraUI");
        file_system_callable_actions = GetNode<Node>("../FileSystemCallableActions");
        base._Ready();
    }
    public override void _focused_input(InputEvent @event) => _operations.focused_input(this);
}
