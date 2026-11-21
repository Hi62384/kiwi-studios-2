using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiGrowthStyle : Resource
{
    [Export] public string title { get; set; } = "Growth style";
    [Export] public string asset_id { get; set; } = ActorData.new_id();
    [Export] public Settings values { get; set; } = new();
    [ThreadStatic] private static Settings? _presets;
    [ThreadStatic] private static GrowthMaterialOperations? _fallback;
    private static GrowthMaterialOperations Operations => Engine.HasSingleton("KiwiNativeServices")
        ? (GrowthMaterialOperations)((MigrationBootstrap)Engine.GetSingleton("KiwiNativeServices")).service("growth_material")
        : _fallback ??= new GrowthMaterialOperations();

    public static Settings presets() => _presets ??= BuildPresets();
    private static Settings BuildPresets()
    {
        var result = new Settings();
        {
            var data = new Settings { ["shape"] = 0, ["curvature"] = 0.0, ["orientation_variation"] = 0.03 };
            data.MakeReadOnly();
            result["Straight"] = data;
        }
        {
            var data = new Settings { ["shape"] = 2, ["curl"] = 0.5, ["frequency"] = 2.0, ["curvature"] = 0.1 };
            data.MakeReadOnly();
            result["Wavy"] = data;
        }
        {
            var data = new Settings { ["shape"] = 3, ["curl"] = 1.2, ["frequency"] = 4.0, ["curvature"] = 0.1 };
            data.MakeReadOnly();
            result["Curly"] = data;
        }
        {
            var data = new Settings { ["shape"] = 3, ["curl"] = 2.0, ["frequency"] = 8.0, ["quality"] = 3 };
            data.MakeReadOnly();
            result["Coiled"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.035, ["shape"] = 0, ["direction_mode"] = 0, ["variation"] = 0.15 };
            data.MakeReadOnly();
            result["Buzzed"] = data;
        }
        {
            var data = new Settings { ["shape"] = 1, ["direction_mode"] = 2, ["direction"] = new Vector3(1f,0.25f,0f), ["direction_blend"] = 0.8 };
            data.MakeReadOnly();
            result["Swept"] = data;
        }
        {
            var data = new Settings { ["shape"] = 2, ["curl"] = 0.4, ["frequency"] = 2.0, ["variation"] = 0.65, ["orientation_variation"] = 0.7 };
            data.MakeReadOnly();
            result["Messy"] = data;
        }
        {
            var data = new Settings { ["shape"] = 1, ["thickness"] = 0.06, ["taper"] = 0.8, ["cross_section"] = 1, ["quality"] = 1 };
            data.MakeReadOnly();
            result["Stylized locks"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.04, ["thickness"] = 0.003, ["variation"] = 0.2, ["guard_hairs"] = 0.05 };
            data.MakeReadOnly();
            result["Short fur"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.12, ["thickness"] = 0.006, ["variation"] = 0.3, ["guard_hairs"] = 0.15 };
            data.MakeReadOnly();
            result["Medium fur"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.3, ["thickness"] = 0.007, ["variation"] = 0.35, ["guard_hairs"] = 0.2 };
            data.MakeReadOnly();
            result["Long fur"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.4, ["variation"] = 0.65, ["orientation_variation"] = 0.6, ["shape"] = 2 };
            data.MakeReadOnly();
            result["Shaggy fur"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.2, ["thickness"] = 0.004, ["direction_mode"] = 0, ["orientation_variation"] = 0.6 };
            data.MakeReadOnly();
            result["Fluffy fur"] = data;
        }
        {
            var data = new Settings { ["length"] = 0.16, ["thickness"] = 0.012, ["cross_section"] = 2, ["guard_hairs"] = 0.35 };
            data.MakeReadOnly();
            result["Coarse fur"] = data;
        }
        {
            var data = new Settings { ["feather_type"] = 0, ["width"] = 0.08, ["length"] = 0.2, ["variation"] = 0.4 };
            data.MakeReadOnly();
            result["Down"] = data;
        }
        {
            var data = new Settings { ["feather_type"] = 1, ["width"] = 0.14, ["length"] = 0.45, ["feather_asymmetry"] = 0.0 };
            data.MakeReadOnly();
            result["Contour"] = data;
        }
        {
            var data = new Settings { ["feather_type"] = 2, ["width"] = 0.16, ["length"] = 0.6, ["feather_asymmetry"] = 0.4 };
            data.MakeReadOnly();
            result["Flight"] = data;
        }
        {
            var data = new Settings { ["feather_type"] = 1, ["width"] = 0.16, ["length"] = 1.0, ["feather_tip"] = 0.4 };
            data.MakeReadOnly();
            result["Tail"] = data;
        }
        {
            var data = new Settings { ["feather_type"] = 1, ["width"] = 0.22, ["length"] = 0.5, ["quality"] = 1, ["feather_tip"] = 0.7 };
            data.MakeReadOnly();
            result["Stylized feathers"] = data;
        }
        result.MakeReadOnly();
        return result;
    }
    public static KiwiGrowthStyle preset(string name) => (KiwiGrowthStyle)Operations.style_preset(name);
    public Texture2D thumbnail() => Operations.texture(this, null);
}
