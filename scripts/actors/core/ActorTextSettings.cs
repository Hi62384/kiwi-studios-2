using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorTextSettings : RefCounted
{
    internal static Settings Fonts { get; } = new();
    internal static string[] Families { get; set; } = System.Array.Empty<string>();
    public static string[] system_fonts() => new ActorTextSettingsOperations().system_fonts();
    public static Settings values(Variant reference) => new ActorTextSettingsOperations().values(reference);
    public static Font font(Settings settings) => new ActorTextSettingsOperations().font(settings);
    public static void apply_label(Label label, Settings settings) => new ActorTextSettingsOperations().apply_label(label, settings);
    internal static void ClearCaches() { Fonts.Clear(); Families = System.Array.Empty<string>(); }
}
