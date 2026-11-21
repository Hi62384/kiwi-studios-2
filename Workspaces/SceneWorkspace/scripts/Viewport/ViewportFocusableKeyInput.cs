using Godot;

[GlobalClass]
public partial class ViewportFocusableKeyInput : FocusableKeyInput
{
    public FreecamController? freecam { get; set; }
    public ProgressBar? freecam_speed_bar { get; set; }
    public Label? freecam_speed_label { get; set; }
    public long _speed_display_id { get; set; }
    private SceneTreeTimer? _speedTimer;
    private readonly ViewportFocusableInputOperations _operations = new();
    private Callable TimerCallback => new(this, nameof(_finish_freecam_speed));
    public override void _Ready()
    {
        freecam = GetNode<FreecamController>("../../../../../../../World/SubViewport/Freecam");
        freecam_speed_bar = GetNode<ProgressBar>("../FreecamSpeedBar");
        freecam_speed_label = GetNode<Label>("../FreecamSpeedBar/FreecamSpeedLabel");
        base._Ready();
    }
    public override void _Process(double delta) => _operations.process(this, delta);
    public override void _focused_input(InputEvent @event) => _operations.focused_input(this, @event);
    private void DisconnectTimer()
    {
        if (GodotObject.IsInstanceValid(_speedTimer) && _speedTimer!.IsConnected("timeout", TimerCallback)) _speedTimer.Disconnect("timeout", TimerCallback);
        _speedTimer = null;
    }
    public void _display_freecam_speed()
    {
        _operations.display_speed(this); DisconnectTimer();
        _speedTimer = GetTree().CreateTimer(2);
        _speedTimer.Connect("timeout", TimerCallback, (uint)ConnectFlags.OneShot);
    }
    public void _finish_freecam_speed()
    {
        if (GodotObject.IsInstanceValid(_speedTimer) && _speedTimer!.TimeLeft > 0) return;
        _speedTimer = null;
        if (IsInsideTree() && GodotObject.IsInstanceValid(freecam_speed_bar)) _operations.finish_display(this, _speed_display_id);
    }
    public override void _ExitTree() { DisconnectTimer(); base._ExitTree(); }
}
