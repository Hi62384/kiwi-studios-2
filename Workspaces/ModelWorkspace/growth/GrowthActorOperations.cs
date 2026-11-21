using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthActorOperations : RefCounted
{
    private static readonly string[] Appearance = { "root_color", "tip_color", "highlight_color", "roughness", "specular", "secondary_highlight", "highlight_shift", "backlight", "opacity", "emission", "variation", "pattern_scale", "pattern_rotation", "pattern_mix", "texture_scale", "texture_offset", "texture_rotation", "bands", "edge_softness", "outline", "shaft_color", "feather_detail", "iridescence", "left_vane_color", "right_vane_color", "feather_pattern_color", "feather_pattern_scale", "feather_pattern_width", "shaft_roughness" };
    private static Resource Property(string id, string title, Variant value, bool animated)
    {
        var property = new ActorProperty(); property.Set("id", new StringName(id)); property.Set("label", title); property.Set("value_type", (int)value.VariantType); property.Set("animatable", animated); property.Set("options", new Settings { ["default"] = value }); return property;
    }
    private static Settings Options(Resource property) => property.Get("options").AsGodotDictionary();
    private static Settings Visible(string property, params Variant[] values) => new() { ["property"] = property, ["values"] = new GArray(values) };
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static bool ScriptType(GodotObject value, string path)
    { var script = value.GetScript().As<Script>(); while (script != null) { if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script = script.GetBaseScript(); } return false; }
    public void extend_actor(Resource definition)
    {
        if (definition.Get("type_id").AsString() != "basic_mesh") return; var properties = definition.Get("properties").AsGodotArray(); foreach (var value in properties) if (value.As<Resource>().Get("id").AsString() == "is_surface_growth") return;
        foreach (var (id, title, value) in new[] { ("is_surface_growth", "Surface growth", Variant.From(false)), ("growth_kind", "Growth type", Variant.From(0)) })
        { var property = Property(id, title, value, false); var options = Options(property); options["inspector_hidden"] = true; options["group"] = "Growth appearance"; properties.Add(property); }
        var defaults = new KiwiGrowthMaterial();
        foreach (string field in Appearance)
        {
            Variant value = defaults.Get(field); var property = Property("growth_" + field, field.Replace('_', ' ').Capitalize(), value, true); var options = Options(property); options["group"] = "Growth appearance"; options["visible_when"] = Visible("is_surface_growth", true); var all = new GArray { Visible("growth_rendering_mode", 0, 1) }; options["visible_when_all"] = all;
            if (field.StartsWith("feather_", StringComparison.Ordinal) || field is "shaft_color" or "shaft_roughness" or "left_vane_color" or "right_vane_color" or "iridescence") all.Add(Visible("growth_kind", 2));
            if (value.VariantType is Variant.Type.Float or Variant.Type.Int) { options["min"] = 0.0; options["max"] = 1.0; options["step"] = .01; }
            if (field is "pattern_scale" or "pattern_rotation" or "texture_rotation" or "feather_pattern_scale") { options["min"] = -100.0; options["max"] = 100.0; }
            if (field == "bands") { options["min"] = 1; options["max"] = 8; options["step"] = 1; }
            if (field == "highlight_shift") { options["min"] = -.8; options["max"] = .8; } properties.Add(property);
        }
        var mode = Property("growth_rendering_mode", "Rendering mode", 0, false); mode.Set("options", new Settings { ["default"] = 0, ["group"] = "Growth appearance", ["choices"] = new GArray { "Realistic", "Stylized / M2DO", "Custom" }, ["visible_when"] = Visible("is_surface_growth", true), ["refresh_inspector"] = true, ["no_keyframes"] = true }); properties.Add(mode);
        var custom = Property("growth_custom_material", "Custom material", default, false); custom.Set("object_type", new StringName("material")); Options(custom)["group"] = "Growth appearance"; Options(custom)["visible_when_all"] = new GArray { Visible("is_surface_growth", true), Visible("growth_rendering_mode", 2) }; properties.Add(custom);
    }
    public void initialize(GodotObject actor, Resource data)
    {
        var values = actor.Get("values").AsGodotDictionary(); values[new StringName("is_surface_growth")] = true; values[new StringName("growth_kind")] = Get(data.Get("settings").AsGodotDictionary(), "type", 0).AsInt32(); var appearance = data.Get("appearance").As<Resource>(); if (appearance == null) return;
        foreach (string field in Appearance) values[new StringName("growth_" + field)] = appearance.Get(field); values[new StringName("growth_rendering_mode")] = appearance.Get("mode");
        if (appearance.Get("custom_asset").As<Resource>() is Resource asset) values[new StringName("growth_custom_material")] = ActorObjectReference.from_object((ActorObjectData)asset.Call("copy_object").As<Resource>());
    }
    public void apply(Node runtime, Settings values)
    {
        if (!Get(values, "is_surface_growth", false).AsBool()) return;
        foreach (var node in runtime.FindChildren("*", "MeshInstance3D", true, false))
        {
            if (!ScriptType(node, "res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd")) continue; var data = node.Get("data").As<Resource>(); var appearance = data.Get("appearance").As<Resource>(); if (appearance == null) continue;
            foreach (string field in Appearance) if (values.TryGetValue(new StringName("growth_" + field), out var value)) appearance.Set(field, value);
            var reference = Get(values, "growth_custom_material"); Resource? asset = null;
            if (reference.VariantType == Variant.Type.Object && reference.AsGodotObject() is GodotObject obj && ScriptType(obj, "res://scripts/actors/core/actor_object_reference.gd")) asset = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("resolve_reference", reference).As<Resource>();
            if (appearance.Get("custom_asset").As<Resource>() != null && asset == null) appearance.Set("custom", default(Variant)); appearance.Set("custom_asset", asset != null ? Variant.From(asset) : default); appearance.Set("mode", Get(values, "growth_rendering_mode", 0).AsInt32()); node.Call("update_growth");
        }
    }
}
