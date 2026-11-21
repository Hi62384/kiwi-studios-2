using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorRegistry : RefCounted
{
    public Settings _definitions { get; set; } = new();
    public Settings _object_definitions { get; set; } = new();
    private readonly ActorDefinitionOperations _operations = new();
    public bool register(ActorDefinition? definition) => _operations.register(this, definition);
    public ActorDefinition? get_definition(StringName type_id) => _operations.get_definition(this, type_id) as ActorDefinition;
    public Godot.Collections.Array<ActorDefinition> get_definitions()
    {
        var result = new Godot.Collections.Array<ActorDefinition>();
        foreach (var value in _operations.get_definitions(this)) result.Add((ActorDefinition)value.As<Resource>());
        return result;
    }
    public bool register_object(ActorObjectDefinition? definition) => _operations.register_object(this, definition);
    public ActorObjectDefinition? get_object_definition(StringName type_id) => _operations.get_object_definition(this, type_id) as ActorObjectDefinition;
    public Godot.Collections.Array<ActorObjectDefinition> object_definitions_for(StringName base_type)
    {
        var result = new Godot.Collections.Array<ActorObjectDefinition>();
        foreach (var value in _operations.object_definitions_for(this, base_type)) result.Add((ActorObjectDefinition)value.As<Resource>());
        return result;
    }
    public bool object_type_matches(StringName type_id, StringName base_type) => _operations.object_type_matches(this, type_id, base_type);
}
