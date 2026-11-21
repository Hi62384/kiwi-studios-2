using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorMediaPreview : VBoxContainer
{
    public string path { get; set; } = "";
    public bool video { get; set; }
    public double duration { get; set; }
    public double time { get; set; }
    public bool playing { get; set; }
    public TextureRect image { get; set; } = new();
    public AudioStreamPlayer player { get; set; } = new();
    public HSlider seek { get; set; } = new();
    public Button transport { get; set; } = new();
    public Settings audio_job { get; set; } = new();
    public string audio_path { get; set; } = "";
    private readonly ActorMediaPreviewOperations _operations = new();
    public override void _Notification(int what)
    {
        if (what != NotificationPredelete) return;
        foreach (var control in new Node[] { image, player, seek, transport })
            if (GodotObject.IsInstanceValid(control) && control.GetParent() == null) control.Free();
    }
    public override void _Ready() => _operations.ready(this);
    public override void _Process(double delta) => _operations.process(this, delta);
    public override void _ExitTree() => _operations.exit_tree(this);
}
