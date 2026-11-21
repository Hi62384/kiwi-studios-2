using Godot;

[GlobalClass]
public partial class ActorObjectDefinition : Resource
{
    [Export] public StringName type_id { get; set; } = new("");
    [Export] public StringName base_type { get; set; } = new("");
    [Export] public string display_name { get; set; } = "";
    [Export] public int schema_version { get; set; } = 1;
    [Export] public Godot.Collections.Array<ActorProperty> properties { get; set; } = new();
    private readonly ActorDefinitionOperations _operations = new();
    public ActorProperty? find_property(StringName property_id) => _operations.find_property(this, property_id) as ActorProperty;
    public Variant value_for(ActorObjectData? data, ActorProperty property) => _operations.value_for(data, property);
    public ActorObjectData create_object() => (ActorObjectData)_operations.create_object(this);
    public bool set_property_value(ActorObjectData data, StringName property_id, Variant value) => _operations.set_object_property(this, data, property_id, value);
}
