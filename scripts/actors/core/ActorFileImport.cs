using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorFileImport : RefCounted
{
    public static StringName type_for_path(string path) => new ActorFileImportOperations().type_for_path(path);
    public static double scene_duration(ActorSceneData? scene) => new ActorFileImportOperations().scene_duration(scene);
    public static Settings values_for_path(string path, ActorRegistry registry) => new ActorFileImportOperations().values_for_path(path, registry);
    public static ActorObjectData environment_from_native(Environment native, ActorRegistry registry)
        => (ActorObjectData)new ActorFileImportOperations().environment_from_native(native, registry);
}
