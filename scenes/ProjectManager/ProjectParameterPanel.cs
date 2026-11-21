using Godot;
using System.Threading.Tasks;

public partial class ProjectParameterPanel : Panel
{
    [Export] public Button close_button { get; set; } = null!;
    [Export] public Button select_button { get; set; } = null!;
    [Export] public Godot.Collections.Array<Resource> mappings { get; set; } = new();
    [Export] public Godot.Collections.Dictionary _state { get; set; } = new();
    [Export] public CheckButton? create_new_folder { get; set; }

    public override void _Ready()
    {
        close_button.Pressed += () => _state["badboy"] = true;
        select_button.Pressed += () => _state["finished"] = true;
        create_new_folder = GetNodeOrNull<CheckButton>("VBoxContainer/HBoxContainer2/CheckButton");
        var browse = GetNodeOrNull<Button>("VBoxContainer/HBoxContainer3/Button");
        if (create_new_folder == null || browse == null) return;
        var path = GetNode<LineEdit>("VBoxContainer/HBoxContainer3/LineEdit2");
        var name = GetNode<LineEdit>("VBoxContainer/LineEdit");
        create_new_folder.Toggled += enabled => path.Text = enabled ? path.Text.PathJoin(name.Text) : path.Text.GetBaseDir();
        browse.Pressed += async () =>
        {
            var picker = GetNode<FileDialog>("../FileDialog");
            var completion = new TaskCompletionSource<string>();
            void Selected(string value) => completion.TrySetResult(value);
            void Canceled() => completion.TrySetResult("");
            picker.FileSelected += Selected; picker.DirSelected += Selected; picker.Canceled += Canceled;
            try { picker.PopupCentered(); string chosen = await completion.Task; if (chosen.Length > 0) path.Text = chosen; }
            finally { picker.FileSelected -= Selected; picker.DirSelected -= Selected; picker.Canceled -= Canceled; }
        };
    }
}
