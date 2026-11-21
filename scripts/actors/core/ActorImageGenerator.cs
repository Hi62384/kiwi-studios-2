using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorImageGenerator : RefCounted
{
    public static readonly int[] RESOLUTIONS = { 64, 128, 256, 512 };
    internal static Settings NoiseImageCache { get; } = new();
    internal static Settings NoiseTextureCache { get; } = new();
    internal static void ClearCaches() { NoiseImageCache.Clear(); NoiseTextureCache.Clear(); }
    public static Image? image_for_object(ActorObjectData? data) => new ActorImageGeneratorOperations().image_for_object(data);
    public static Texture2D? texture_for_object(ActorObjectData? data) => new ActorImageGeneratorOperations().texture_for_object(data);
    public static Image? image_from_value(Variant value) => new ActorImageGeneratorOperations().image_from_value(value);
    public static Image? generate_noise(ActorObjectData data) => new ActorImageGeneratorOperations().generate_noise(data);
}
