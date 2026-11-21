using Godot;

[GlobalClass]
public partial class LiveColorPickerButton : ColorPickerButton
{
    [Signal] public delegate void interaction_startedEventHandler();
    [Signal] public delegate void interaction_endedEventHandler();
    [Signal] public delegate void preview_changedEventHandler(Color value);
    [Signal] public delegate void drag_committedEventHandler(Color original, Color value);
    [Signal] public delegate void drag_cancelledEventHandler(Color original);
    public bool dragging { get; set; }
    public Color _origin { get; set; } = Colors.Black;
    public Color _pending_origin { get; set; } = Colors.Black;
    public bool _session_active { get; set; }
    public bool _suppress_preview { get; set; }
    public ColorRect? _swatch { get; set; }
    private readonly LiveColorPickerOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public override void _Input(InputEvent @event) => _operations.input(this, @event);
    public override void _Process(double delta) => _operations.process(this);
    public void begin_session() => _operations.begin_session(this);
    public void begin_drag() => _operations.begin_drag(this);
    public void _on_color_changed(Color value) => _operations.on_color_changed(this, value);
    public void _on_popup_closed() => _operations.on_popup_closed(this);
    public void finish_drag() => _operations.finish_drag(this);
    public void cancel_drag() => _operations.cancel_drag(this);
    public void set_color_silent(Color value) => _operations.set_color_silent(this, value);
    public void _update_swatch(Color value) => _operations.update_swatch(this, value);
    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut || what == NotificationExitTree) cancel_drag();
    }
}
