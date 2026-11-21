using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class DestructionControl : VBoxContainer
{
    public Control? host { get; set; }
    public ActorData? actor { get; set; }
    public string selected { get; set; } = "";
    public long layout { get; set; } = -1;
    public bool queued { get; set; }
    public Variant _sync_callback { get; set; }
    public Godot.Collections.Array<Callable> callbacks { get; set; } = new();
    private readonly DestructionControlOperations _operations = new();
    public void setup(Control inspector, ActorData data) => _operations.setup(this, inspector, data);
    public void sync() => _operations.sync(this);
    public void build() => _operations.build(this);
    public override void _ExitTree() => _operations.exit_tree(this);
    public void commit_drag(string id, string key, Variant value, Settings before) => _operations.commit_drag(this, id, key, value, before);
    public void cancel_drag(string id, string key, Settings before) => _operations.cancel_drag(this, id, key, before);
    public void change(string id, string key, Variant value) => change(id, key, value, false);
    public void change(string id, string key, Variant value, bool preview) => _operations.change(this, id, key, value, preview);
}
