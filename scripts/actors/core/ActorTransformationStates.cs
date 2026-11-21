using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ActorTransformationStates : RefCounted
{
    internal static Settings Assets { get; } = new();
    public static string source_path(ActorData actor) => new ActorTransformationStateOperations().source_path(actor);
    public static void invalidate(string path) => new ActorTransformationStateOperations().invalidate(Assets, path);
    public static Settings load_asset(ActorData actor) => new ActorTransformationStateOperations().load_asset(Assets, actor);
    public static string[] path_for(string componentId) => new ActorTransformationStateOperations().path_for(componentId);
    public static string current(ActorData actor, KiwiTransformationComponent item, double time) => new ActorTransformationStateOperations().current(actor, item, time);
    public static ActorProperty property_for(KiwiTransformationComponent item) => (ActorProperty)new ActorTransformationStateOperations().property_for(item);
    public static Settings capture(RefCounted model, ActorData actor) => new ActorTransformationStateOperations().capture(model, actor);
    public static void restore(RefCounted model, GArray snapshots) => new ActorTransformationStateOperations().restore(model, snapshots);
    public static void choose(RefCounted model, ActorData actor, KiwiTransformationComponent item, string stateId) => new ActorTransformationStateOperations().choose(model, actor, item, stateId);
    public static Settings samples(ActorData actor, KiwiTransformationImage2D document, double time, Settings values) => new ActorTransformationStateOperations().samples(actor, document, time, values);
    internal static void ClearCaches() => Assets.Clear();
}
