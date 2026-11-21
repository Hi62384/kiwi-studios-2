using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorObjectData : Resource
{
    [Export] public StringName type_id { get; set; } = new("");
    [Export] public int schema_version { get; set; } = 1;
    [Export] public Settings values { get; set; } = new();
    private readonly ActorDataOperations _operations = new();
    public void set_value(StringName property_id, Variant value) => _operations.set_value(this, property_id, value);
    public Variant get_value(StringName property_id) => _operations.object_get_value(this, property_id, default);
    public Variant get_value(StringName property_id, Variant fallback) => _operations.object_get_value(this, property_id, fallback);
    public ActorObjectData copy_object() => (ActorObjectData)_operations.copy_object(this);
}
