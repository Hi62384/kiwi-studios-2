using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ActorObjectReference : Resource
{
    public enum Source { EMBEDDED, ASSET }
    [Export] public Source source { get; set; } = Source.EMBEDDED;
    [Export] public StringName object_type { get; set; } = new("");
    [Export] public ActorObjectData? embedded { get; set; }
    [Export] public string asset_id { get; set; } = "";
    private readonly ActorDataOperations _operations = new();

    public static ActorObjectReference from_object(ActorObjectData data) => new() { object_type = data.type_id, embedded = data };
    public static ActorObjectReference from_asset(string id, StringName type) => new() { source = Source.ASSET, object_type = type, asset_id = id };
    public static Settings source_modes() => new() { ["EMBEDDED"] = (int)Source.EMBEDDED, ["ASSET"] = (int)Source.ASSET };
    public ActorObjectData? resolve() => _operations.resolve(this, default) as ActorObjectData;
    public ActorObjectData? resolve(Variant resolve_asset) => _operations.resolve(this, resolve_asset) as ActorObjectData;
    public ActorObjectReference? make_unique() => _operations.make_unique(this, default) as ActorObjectReference;
    public ActorObjectReference? make_unique(Variant resolve_asset) => _operations.make_unique(this, resolve_asset) as ActorObjectReference;
    public ActorObjectReference copy_reference() => (ActorObjectReference)_operations.copy_reference(this);

    // Keep incoming GDScript callables in their original Variant representation.
    // Engine-side invocation also supports native callables without conversion.
    public Variant _resolve_asset(Variant resolver)
    {
        using var arguments = new GArray { asset_id };
        return EngineVariantDispatch.InvokeCallable(resolver, arguments);
    }
}
