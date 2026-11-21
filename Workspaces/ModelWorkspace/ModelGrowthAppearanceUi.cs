using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceOperations
{
    public void growth_appearance(Control workspace, Node parent, Resource data)
    {
        if (data.Get("appearance").As<Resource>() == null) _growth.render(data, Array.Empty<Vector3>()); var material = data.Get("appearance").As<Resource>(); var session = Session(workspace);
        Label(parent, "RENDERING & MATERIAL"); growth_name_field(workspace, parent, material); var presets = new OptionButton { Name = "GrowthAppearancePreset", FitToLongestItem = false }; parent.AddChild(presets); presets.AddItem("Appearance presets…");
        foreach (string title in new[] { "Black hair", "Warm hair", "Pale fur", "Striped coat", "Flight feathers", "Iridescent feathers", "Stylized ink" }) { var preset = _growthMaterials.preset(title); presets.AddIconItem(_growthMaterials.texture(null, preset), title); }
        presets.ItemSelected += index => { if (index > 0) Action(session, "Apply growth appearance preset", () => data.Set("appearance", _growthMaterials.preset(presets.GetItemText((int)index)))); };
        OptionButton Choice(string[] titles, int selected, Action<int> setter, string name = "")
        {
            var input = new OptionButton { FitToLongestItem = false }; if (name.Length > 0) input.Name = name; parent.AddChild(input); foreach (string title in titles) input.AddItem(title); input.Select(selected); input.ItemSelected += index => setter((int)index); return input;
        }
        int mode = material.Get("mode").AsInt32(); Choice(new[] { "Realistic", "Stylized / M2DO", "Custom material" }, mode, index => Action(session, "Growth rendering mode", () => material.Set("mode", index)), "GrowthRenderingMode");
        if (mode == 2) { Label(parent, "Custom shading supplies its own appearance. Geometry and root attachment remain editable."); growth_asset_actions(workspace, parent, data); return; }
        Choice(new[] { "Stable cutout / automatic translucency", "Alpha hash coverage", "Alpha to coverage · needs MSAA" }, material.Get("coverage").AsInt32(), index => Action(session, "Growth coverage", () => material.Set("coverage", index)));
        var rendering = GrowthDict(data, "rendering"); var lod = new CheckButton { Name = "GrowthAutomaticLOD", Text = "Distance detail", ButtonPressed = GrowthValue(rendering, "automatic_lod", true).AsBool() }; parent.AddChild(lod); lod.Toggled += next => Action(session, "Growth distance detail", () => rendering["automatic_lod"] = next);
        if (lod.ButtonPressed) foreach (var (field, title, minimum, maximum, fallback) in new[] { ("near", "Full detail distance", .1, 1000.0, 4.0), ("far", "Far detail distance", .2, 10000.0, 16.0), ("minimum_density", "Distant coverage", .05, 1.0, .15) }) Number(workspace, parent, title, GrowthValue(rendering, field, fallback).AsDouble(), minimum, maximum, .01, next => rendering[field] = next);
        var section = Choice(new[] { "Color & highlights", "Coat pattern", "Feather appearance", "Textures", "Stylized shading", "Root-to-tip gradient" }, workspace.GetMeta("growth_material_section", 0).AsInt32(), index => { workspace.SetMeta("growth_material_section", index); workspace.Set("_refresh_pending", true); });
        (string Field, string Title)[] colors = Array.Empty<(string, string)>(); (string Field, string Title, double Min, double Max)[] numbers = Array.Empty<(string, string, double, double)>();
        switch (section.Selected)
        {
            case 0:
                colors = new[] { ("root_color", "Roots"), ("tip_color", "Tips"), ("highlight_color", "Highlights"), ("emission", "Emission") };
                numbers = new[] { ("roughness", "Roughness", .04, 1.0), ("specular", "Primary highlight", 0.0, 1.0), ("secondary_highlight", "Secondary highlight", 0.0, 1.0), ("highlight_shift", "Highlight shift", -.8, .8), ("backlight", "Backlighting", 0.0, 1.0), ("opacity", "Coverage", 0.0, 1.0), ("variation", "Strand color variation", 0.0, 1.0) }; break;
            case 1:
                Choice(new[] { "No pattern", "Stripes", "Spots", "Speckles", "Mottle", "Patches" }, material.Get("pattern").AsInt32(), index => Action(session, "Growth coat pattern", () => material.Set("pattern", index)));
                colors = new[] { ("pattern_color", "Pattern color") }; numbers = new[] { ("pattern_scale", "Pattern scale", .01, 100.0), ("pattern_rotation", "Pattern rotation", -Math.PI, Math.PI), ("pattern_mix", "Pattern blend", 0.0, 1.0), ("pattern_seed", "Pattern seed", 0.0, 10000.0) }; break;
            case 2:
                colors = new[] { ("shaft_color", "Shaft color"), ("left_vane_color", "Left vane tint"), ("right_vane_color", "Right vane tint"), ("feather_pattern_color", "Marking color") };
                numbers = new[] { ("feather_detail", "Vane detail", 0.0, 1.0), ("iridescence", "Iridescence", 0.0, 1.0), ("shaft_roughness", "Shaft roughness", .04, 1.0), ("feather_pattern_scale", "Marking scale", .1, 40.0), ("feather_pattern_width", "Marking width", 0.0, 1.0) };
                Choice(new[] { "No markings", "Bands", "Spots", "Edges", "Tips", "Speckles" }, material.Get("feather_pattern").AsInt32(), index => Action(session, "Feather markings", () => material.Set("feather_pattern", index))); break;
            case 3:
                GrowthTextureControls(workspace, parent, material);
                foreach (string field in new[] { "texture_scale", "texture_offset" }) for (int axis = 0; axis < 2; axis++) { int at = axis; Number(workspace, parent, field.Capitalize() + " " + "XY"[at], material.Get(field).AsVector2()[at], -100, 100, .01, next => { Vector2 vector = material.Get(field).AsVector2(); vector[at] = (float)next; material.Set(field, vector); }); }
                numbers = new[] { ("texture_rotation", "Texture rotation", -Math.PI, Math.PI) }; break;
            case 4: colors = new[] { ("outline_color", "Outline color") }; numbers = new[] { ("bands", "Lighting bands", 1.0, 8.0), ("edge_softness", "Band softness", 0.0, .49), ("outline", "Vane / card edge width", 0.0, .4) }; break;
            case 5: GrowthGradient(workspace, parent, material); break;
        }
        foreach (var (field, title) in colors) GrowthColor(workspace, parent, title, material.Get(field).AsColor(), next => material.Set(field, next), "Growth" + field.ToPascalCase());
        foreach (var (field, title, minimum, maximum) in numbers) Number(workspace, parent, title, material.Get(field).AsDouble(), minimum, maximum, field is "bands" or "pattern_seed" ? 1 : .01, next => material.Set(field, field == "bands" ? Variant.From((int)next) : Variant.From(next)));
        growth_asset_actions(workspace, parent, data);
    }
    private void GrowthGradient(Control workspace, Node parent, Resource material)
    {
        var session = Session(workspace); var gradient = material.Get("gradient").As<Gradient>();
        if (gradient == null) { AddButton(parent, "Create multicolor gradient", () => Action(session, "Create growth gradient", () => material.Set("gradient", new Gradient { Colors = new[] { material.Get("root_color").AsColor(), material.Get("tip_color").AsColor() } }))); return; }
        for (int index = 0; index < gradient.GetPointCount(); index++)
        {
            int at = index; var input = new ColorPickerButton { Color = gradient.GetColor(at), CustomMinimumSize = new Vector2(0, 24) }; parent.AddChild(input); Color before = input.Color;
            input.ColorChanged += next => gradient.SetColor(at, next); input.PopupClosed += () => { Color after = input.Color; gradient.SetColor(at, before); Action(session, "Growth gradient color", () => gradient.SetColor(at, after)); before = after; };
            double low = at > 0 ? gradient.GetOffset(at - 1) + .001 : 0, high = at < gradient.GetPointCount() - 1 ? gradient.GetOffset(at + 1) - .001 : 1;
            Number(workspace, parent, "Stop position", gradient.GetOffset(at), low, high, .001, next => gradient.SetOffset(at, (float)next));
            if (gradient.GetPointCount() > 2) AddButton(parent, "Remove stop", () => Action(session, "Remove gradient stop", () => gradient.RemovePoint(at)));
        }
        AddButton(parent, "Add gradient stop", () => Action(session, "Add gradient stop", () =>
        {
            float at = .5f, widest = 0; for (int i = 0; i < gradient.GetPointCount() - 1; i++) { float width = gradient.GetOffset(i + 1) - gradient.GetOffset(i); if (width > widest) { widest = width; at = (gradient.GetOffset(i) + gradient.GetOffset(i + 1)) * .5f; } } gradient.AddPoint(at, gradient.Sample(at));
        }));
        AddButton(parent, "Use root / tip colors", () => Action(session, "Remove growth gradient", () => material.Set("gradient", default(Variant))));
    }
    private void GrowthTextureControls(Control workspace, Node parent, Resource material)
    {
        var session = Session(workspace); var sources = GrowthDict(material, "texture_sources");
        foreach (string field in new[] { "albedo_texture", "roughness_texture", "normal_texture", "alpha_texture" })
        {
            var row = new HBoxContainer(); parent.AddChild(row);
            AddButton(row, field.TrimSuffix("_texture").Capitalize() + "…", async () =>
            {
                var property = GrowthProperty(new Settings { ["extensions"] = new GArray { "png", "jpg", "jpeg", "webp", "tres", "res" }, ["accepted_object_types"] = new GArray { "image", "noise_image" }, ["native_resource_types"] = new GArray { "Texture2D" } }); property.Set("object_type", new StringName("image"));
                string path = await GrowthPick(workspace, property, "Choose growth texture"); if (path.Length == 0 || !GrowthCurrent(workspace, session)) return; Texture2D? texture = null;
                if (path != "::empty-resource::")
                {
                    if (path.GetExtension() is "tres" or "res")
                    {
                        var loaded = ResourceLoader.Load(path); texture = loaded is Texture2D native ? native : loaded != null && loaded.HasMethod("get_value") ? GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("texture_for_object", loaded).As<Texture2D>() : null;
                    }
                    else { var image = Image.LoadFromFile(path); if (image != null) { image.GenerateMipmaps(); texture = ImageTexture.CreateFromImage(image); } }
                }
                Action(session, "Growth texture", () => { material.Set(field, texture != null ? Variant.From(texture) : default); if (path != "::empty-resource::") sources[field] = path; else sources.Remove(field); });
            });
            AddButton(row, "×", () => Action(session, "Clear growth texture", () => { material.Set(field, default(Variant)); sources.Remove(field); }));
            AddButton(row, "Noise", () => Action(session, "Create growth noise texture", () => { material.Set(field, new NoiseTexture2D { Width = 256, Height = 256, GenerateMipmaps = true, Noise = new FastNoiseLite { Frequency = .025f } }); sources.Remove(field); }));
            if (material.Get(field).AsGodotObject() is NoiseTexture2D generated && generated.Noise is FastNoiseLite noise)
            {
                Number(workspace, parent, field.TrimSuffix("_texture").Capitalize() + " frequency", noise.Frequency, .0001, 1, .001, next => noise.Frequency = (float)next); Number(workspace, parent, "Noise seed", noise.Seed, 0, 1000000, 1, next => noise.Seed = (int)next);
                var normal = new CheckButton { Text = "Noise as normal map", ButtonPressed = generated.AsNormalMap }; parent.AddChild(normal); normal.Toggled += next => Action(session, "Growth noise normal map", () => generated.AsNormalMap = next);
            }
        }
    }
}
