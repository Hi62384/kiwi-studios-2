using Godot;

[GlobalClass]
public partial class ActorCatalog : Resource
{
    [Export] public Godot.Collections.Array<ActorDefinition> definitions { get; set; } = new();
    [Export] public Godot.Collections.Array<ActorObjectDefinition> object_definitions { get; set; } = new();
    private readonly ActorFileImportOperations _operations = new();
    public bool register_into(ActorRegistry registry) => _operations.register_catalog(this, registry);
}
