using Godot;

[GlobalClass]
public partial class ActorFontPicker : PopupPanel
{
    [Signal] public delegate void font_chosenEventHandler(string family);
    public LineEdit? search { get; set; }
    public VBoxContainer? options { get; set; }
    public Label? result_count { get; set; }
    public string current_family { get; set; } = "";
    public string[] families { get; set; } = System.Array.Empty<string>();
    public string preview_text { get; set; } = "";
    public bool preview_actual { get; set; }
    private readonly ActorFontPickerOperations _operations = new();
    public void setup(string selected) => _operations.setup(this, selected);
    public void _rebuild(string query) => _operations.rebuild(this, query);
    public void _choose(string family) => _operations.choose(this, family);
    public StyleBoxFlat _box(Color color, Color border, int radius, int width) => _operations.box(color, border, radius, width);
}
