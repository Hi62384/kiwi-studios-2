using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorDefinition : Resource
{
    [Export] public StringName type_id { get; set; } = new("");
    [Export] public string display_name { get; set; } = "";
    [Export] public string category { get; set; } = "General";
    [Export] public string description { get; set; } = "";
    [Export] public Texture2D? icon { get; set; }
    [Export] public int schema_version { get; set; } = 1;
    [Export] public Godot.Collections.Array<ActorProperty> properties { get; set; } = new();
    [Export] public PackedScene? runtime_scene { get; set; }
    private readonly ActorDefinitionOperations _operations = new();
    public ActorProperty? find_property(StringName property_id) => _operations.find_property(this, property_id) as ActorProperty;
    public ActorData create_actor() => (ActorData)_operations.create_actor(this, new Settings());
    public ActorData create_actor(Settings initial_values) => (ActorData)_operations.create_actor(this, initial_values);
    public bool set_property_value(ActorData actor, StringName property_id, Variant value) => _operations.set_actor_property(this, actor, property_id, value);
    public ActorRuntime? create_runtime(ActorData actor) => _operations.create_runtime(this, actor) as ActorRuntime;
}
