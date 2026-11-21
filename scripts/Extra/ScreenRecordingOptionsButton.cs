using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ScreenRecordingOptionsButton : RecordingOptionsButton
{
    [Signal] public delegate void recording_requestedEventHandler(Settings options, Settings target);
    // Keep callbacks as engine Variants: callers may supply GDScript Callables.
    public Variant is_recording { get; set; }
    public Variant stop_recording { get; set; }
    public override void _Ready() => Options.screen_ready(this);
    public override void _add_capture_options(VBoxContainer column) => Options.add_capture_options(this, column);
    public void _screen_pressed()
    {
        using var arguments = new Godot.Collections.Array();
        using var recording = EngineVariantDispatch.InvokeCallable(is_recording, arguments);
        if (recording.VariantType == Variant.Type.Bool && recording.AsBool())
        {
            using var ignored = EngineVariantDispatch.InvokeCallable(stop_recording, arguments);
        }
        else open_settings();
    }
}
