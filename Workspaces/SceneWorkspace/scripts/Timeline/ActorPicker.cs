using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorPicker : PopupPanel
{
    [Signal] public delegate void actor_chosenEventHandler(int index);
    public Godot.Collections.Array<ActorDefinition> definitions { get; set; } = new();
    public LineEdit? search { get; set; }
    public VBoxContainer? cards { get; set; }
    public string category { get; set; } = "All";
    public Label? location_label { get; set; }
    public Label? result_label { get; set; }
    public Godot.Collections.Array<int> _matches { get; set; } = new();
    public Settings expanded { get; set; } = new();
    private readonly ActorPickerOperations _operations = new();
    public void setup(Godot.Collections.Array<ActorDefinition> types)
    {
        using var value = Variant.From(types);
        _operations.setup(this, value.AsGodotArray());
    }
    public void open(int layer, double time) => _operations.open(this, layer, time);
    public void rebuild() => _operations.rebuild(this);
    public int _category_count(string name) => _operations.category_count(this, name);
    public string _category_symbol(string name) => _operations.category_symbol(name);
    public StyleBoxFlat _box(Color color, Color border, int radius, int width) => _operations.box(color, border, radius, width);
    public void choose(int index) => _operations.choose(this, index);
}
