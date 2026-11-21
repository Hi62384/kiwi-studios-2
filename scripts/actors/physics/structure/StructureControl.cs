using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class StructureControl : VBoxContainer
{
    public Control? host { get; set; }
    public ActorData? actor { get; set; }
    public string selected { get; set; } = "";
    public long signature { get; set; }
    public Godot.Collections.Array<Settings> candidates { get; set; } = new();
    public double tolerance { get; set; } = .05;
    public Variant _sync_callback { get; set; }
    public Godot.Collections.Array<Callable> callbacks { get; set; } = new();
    private readonly StructureControlOperations _operations = new();
    public void setup(Control inspector, ActorData data) => _operations.setup(this, inspector, data);
    public Control? editor() => _operations.editor(this);
    public Transform3D pose(ActorData data) => _operations.pose(this, data);
    public void sync() => _operations.sync(this);
    public void build() => _operations.build(this);
    public override void _ExitTree() => _operations.exit_tree(this);
    public void toggle(string id, string key, bool value) => toggle(id, key, value, null);
    public void toggle(string id, string key, bool value, Control? parent) => _operations.toggle(this, id, key, value, parent);
    public void number(string id, string key, double value) => number(id, key, value, null, -1);
    public void number(string id, string key, double value, Control? parent) => number(id, key, value, parent, -1);
    public void number(string id, string key, double value, Control? parent, int axis) => _operations.number(this, id, key, value, parent, axis);
}
