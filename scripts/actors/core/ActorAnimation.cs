using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorAnimation : RefCounted
{
    public static ActorObjectData? resolve_reference(ActorObjectReference reference) => new ActorAnimationOperations().resolve_reference(reference) as ActorObjectData;
    public static Variant value_at_path(ActorData actor, string[] path) => new ActorAnimationOperations().value_at_path(actor, path);
    public static Variant sampled_value(ActorData actor, string[] path, double time) => sampled_value(actor, path, default);
    public static Variant sampled_value(ActorData actor, string[] path, double time, Variant fallback) => new ActorAnimationOperations().sampled_value(actor, path, time, fallback);
    public static Settings sampled_values(ActorData actor, double time) => new ActorAnimationOperations().sampled_values(actor, time);
    public static void _set_path(Settings container, string[] path, Variant value) => _set_path(container, path, value, 0);
    public static void _set_path(Settings container, string[] path, Variant value, int index) => new ActorAnimationOperations().set_path(container, path, value, index);
    public static string[] path_to_object(ActorData actor, ActorObjectData target) => new ActorAnimationOperations().path_to_object(actor, target);
    public static string[] _find_object(Settings values, ActorObjectData target, string[] prefix, Settings visited) => new ActorAnimationOperations().find_object(values, target, prefix, visited);
}
