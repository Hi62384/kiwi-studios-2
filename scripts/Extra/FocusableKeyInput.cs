using Godot;

[GlobalClass]
public partial class FocusableKeyInput : Control
{
    private static FocusableKeyInput? _current;
    public static FocusableKeyInput? current_focused_instance
    {
        get { if (!GodotObject.IsInstanceValid(_current)) _current = null; return _current; }
        set => _current = value;
    }
    public static FocusableKeyInput? focused_instance() => current_focused_instance;
    public static void set_focused_instance(FocusableKeyInput? value) => current_focused_instance = value;
    private readonly FocusableInputOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public bool _is_mouse_inside_self() => _operations.mouse_inside(this);
    public override void _Input(InputEvent @event) => _operations.input(this, @event);
    public bool is_focused() => _operations.is_focused(this);
    public virtual void _focused_input(InputEvent @event) { }
    public override void _ExitTree() => _operations.exit_tree(this);
}
