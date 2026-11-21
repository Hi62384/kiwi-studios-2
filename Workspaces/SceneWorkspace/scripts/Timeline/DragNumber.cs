using Godot;

[GlobalClass]
public partial class DragNumber : SpinBox
{
    [Signal] public delegate void interaction_startedEventHandler();
    [Signal] public delegate void interaction_endedEventHandler();
    [Signal] public delegate void preview_changedEventHandler(double value);
    [Signal] public delegate void drag_committedEventHandler(double value);
    [Signal] public delegate void drag_cancelledEventHandler();
    public bool dragging { get; set; }
    public bool _pressed { get; set; }
    public double _origin { get; set; }
    public double _press_x { get; set; }
    public double _last_x { get; set; }
    public double _remainder { get; set; }
    private readonly DragNumberOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public void _line_edit_input(InputEvent @event) => _operations.line_edit_input(this, @event);
    public void _begin_drag(Vector2 position) => _operations.begin_drag(this, position);
    public override void _Input(InputEvent @event) => _operations.input(this, @event);
    public void drag_pixels(double pixels, bool ctrl, bool shift) => _operations.drag_pixels(this, pixels, ctrl, shift);
    public void _wrap_pointer(Vector2 position) => _operations.wrap_pointer(this, position);
    public static Vector2 wrap_target(Vector2 position, Rect2 bounds) => new DragNumberOperations().wrap_target(position, bounds);
    public void finish_drag() => _operations.finish_drag(this);
    public void cancel_drag() => _operations.cancel_drag(this);
    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut || what == NotificationExitTree) cancel_drag();
    }
}
