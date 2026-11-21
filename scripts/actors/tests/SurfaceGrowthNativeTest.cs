using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class SurfaceGrowthNativeTest : Node
{
    private int _checks;
    private void Check(bool condition, string title) { if (!condition) throw new Exception(title); _checks++; GD.Print("PASS ", title); }
    public override void _Ready()
    {
        try
        {
            using var settings = new SurfaceGrowthSettings(); using var geometry = new SurfaceGrowthGeometry();
            var data = new KiwiSurfaceGrowthData();
            data.Set("settings", settings.defaults(0));
            Check(settings.defaults(0)["length"].AsDouble() == .65 && settings.defaults(1)["density"].AsDouble() == 120 && settings.defaults(2)["width"].AsDouble() == .14, "Native defaults preserve hair, fur and feather profiles");
            var style = new KiwiGrowthStyle(); style.Set("values", new Settings { ["length"] = .7 }); data.Set("growth_style", style);
            var root = new Settings { ["id"] = 3, ["face"] = 5, ["triangle"] = new Vector3I(0, 1, 2), ["bary"] = new Vector3(.2f, .3f, .5f), ["normal"] = Vector3.Up, ["random"] = new Vector4(.5f, .5f, .5f, .5f) };
            Check(settings.root_settings(data, root)["length"].AsDouble() == .7, "Shared growth style overrides base settings");
            style.Get("values").AsGodotDictionary()["length"] = .9;
            Check(settings.root_settings(data, root)["length"].AsDouble() == .9, "Editing shared style invalidates cached regions without a geometry revision");
            var local = new KiwiGrowthStyle(); local.Set("values", new Settings { ["length"] = .2 });
            data.Get("regions").AsGodotArray().Add(new Settings { ["enabled"] = true, ["roots"] = new[] { 3 }, ["style"] = local }); data.Set("revision", 1);
            Check(settings.root_settings(data, root)["length"].AsDouble() == .2, "Regional style overrides shared style for explicit strand IDs");
            data.Set("groom", new Settings { ["3"] = new Settings { ["length"] = .4, ["curl"] = .2 } });
            data.Get("groom_layers").AsGodotArray().Add(new Settings { ["changes"] = new Settings { ["3"] = new Settings { ["length"] = .6 } } });
            data.Set("pending", new Settings { ["3"] = new Settings { ["length"] = .8 } }); data.Set("individual", new Settings { ["3"] = new Settings { ["length"] = 1.2 } });
            Check(geometry.style(data, root)["length"].AsDouble() == 1.2 && geometry.style(data, root)["curl"].AsDouble() == .2, "Individual edits override pending and layered groom while preserving other fields");
            data.Set("groom_enabled", false); Check(geometry.style(data, root)["length"].AsDouble() == 1.2, "Individual strand edits remain active when layered grooming is disabled");
            var points = new[] { Vector3.Zero, Vector3.Right, Vector3.Back };
            var frame = geometry.point_frame(data, root, points);
            Check(frame.Origin.IsEqualApprox(new Vector3(.3f, 0, .5f)) && frame.Basis.Y.IsEqualApprox(Vector3.Up), "Barycentric surface frame preserves attachment position and normal");
            var resampled = geometry.resample_curve(new[] { Vector3.Zero, Vector3.Right, Vector3.Right * 3 }, 4);
            Check(resampled[1].IsEqualApprox(Vector3.Right) && resampled[2].IsEqualApprox(Vector3.Right * 2), "Curve resampling uses arc length rather than point index");
            Check(geometry.resample_curve(Array.Empty<Vector3>(), 2).Length == 2 && geometry.resample_curve(new[] { Vector3.One }, 3)[2] == Vector3.One, "Degenerate guide curves resample safely");
            data.Set("motion_weights", new Settings { ["3"] = new Settings { ["a"] = 1.0, ["b"] = 3.0 } });
            data.Set("motion_guides", new Settings { ["a"] = new Settings { ["delta_points"] = new[] { Vector3.Zero, Vector3.Right } }, ["b"] = new Settings { ["delta_points"] = new[] { Vector3.Zero, Vector3.Up } } });
            Check(geometry.motion_delta(data, root, .5).IsEqualApprox(new Vector3(.125f, .375f, 0)), "Guide motion blends weighted samples with normalized influence");
            using var materials = new GrowthMaterialOperations(); var appearance = materials.preset("Warm hair");
            var noise = new NoiseTexture2D { Noise = new FastNoiseLite { Frequency = .02f } }; appearance.Set("albedo_texture", noise); appearance.Set("gradient", new Gradient());
            var copy = materials.copy_material(appearance, true);
            Check(copy.Get("asset_id").AsString() != appearance.Get("asset_id").AsString() && copy.Get("albedo_texture").As<NoiseTexture2D>() != noise && copy.Get("gradient").As<Gradient>() != appearance.Get("gradient").As<Gradient>(), "Unique material copies preserve independent identities, noise textures and gradients");
            long beforeNoise = materials.signature(appearance); ((FastNoiseLite)noise.Noise).Frequency = .19f;
            Check(materials.signature(appearance) != beforeNoise, "Nested native noise changes invalidate appearance signatures");
            var styles = KiwiGrowthStyle.presets();
            bool thumbnails = true; foreach (var pair in styles)
            {
                var preset = materials.style_preset(pair.Key.AsString()); var texture = materials.texture(preset, null);
                thumbnails &= texture.GetWidth() == 128 && texture.GetHeight() == 128 && !texture.GetImage().IsEmpty();
            }
            Check(thumbnails, "Every saved growth style produces a valid native curve thumbnail");
            var originalPreview = materials.texture(null, appearance); appearance.Set("tip_color", Colors.Magenta);
            Check(materials.texture(null, appearance) != originalPreview, "Material thumbnail cache refreshes when appearance changes");
            GD.Print("NATIVE GROWTH: ", _checks, " checks, 0 failures"); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
