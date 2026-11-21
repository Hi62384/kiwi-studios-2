using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class RecordingOptionsButton : Button
{
    public PopupPanel? popup { get; set; }
    public OptionButton? device { get; set; }
    public Settings preferences { get; set; } = new();
    protected readonly RecordingOptionsOperations Options = new();
    public override void _Ready() => Options.ready(this);
    public void open_settings() => Options.open_settings(this);
    public void _refresh_devices() => Options.refresh_devices(this);
    public virtual void _add_capture_options(VBoxContainer column) { }
}
