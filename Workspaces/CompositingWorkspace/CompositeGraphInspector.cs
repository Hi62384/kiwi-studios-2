using Godot;
using System;

public partial class CompositeGraphInspector : RefCounted
{
    private readonly CompositeInspectorControls _controls = new();
    public bool build(Control parent, Resource document, Resource? graph, string selected, Control workspace)
    {
        using var rules = new CompositeGraph(); var node = graph == null ? null : rules.node_resource(graph, selected);
        if (node == null) { parent.AddChild(new Label { Text = "Select a node to edit its settings." }); return false; }
        string kind = node.Get("kind").AsString(); parent.AddChild(new Label { Text = "NODE · " + kind });
        Variant Value(string key, Variant fallback) { var settings = node.Get("settings").AsGodotDictionary(); return settings.TryGetValue(key, out var value) ? value : fallback; }
        void Set(string key, Variant value)
        {
            var before = (Resource)document.Duplicate(true); var settings = node.Get("settings").AsGodotDictionary(); settings[key] = value; node.Set("settings", settings);
            workspace.Call("_commit", "Change " + kind + " settings", before);
        }
        void Number(string caption, string key, double fallback, double minimum, double maximum, double step, bool integer = false)
        { var field = _controls.number(parent, caption, Value(key, fallback).AsDouble(), minimum, maximum, step); field.ValueChanged += value => Set(key, integer ? Variant.From((int)value) : Variant.From(value)); }
        void ColorField(string caption, string key, Color fallback)
        { var field = _controls.color(parent, caption, Value(key, fallback).AsColor()); field.ColorChanged += value => Set(key, value); }
        void Note(string text) => parent.AddChild(new Label { Text = text, AutowrapMode = TextServer.AutowrapMode.WordSmart });
        switch (kind)
        {
            case "Image Source":
                var path = _controls.line(parent, "Image path", Value("path", "").AsString()); path.TextSubmitted += value => Set("path", value); break;
            case "Layer Source":
                var picker = new OptionButton(); parent.AddChild(picker); int selectedIndex = 0;
                foreach (Variant value in document.Get("layers").AsGodotArray())
                {
                    var layer = value.As<Resource>(); if (layer == null) continue;
                    int index = picker.ItemCount; picker.AddItem(layer.Get("name").AsString()); picker.SetItemMetadata(index, layer.Get("id"));
                    if (layer.Get("id").AsString() == Value("layer_id", "").AsString()) selectedIndex = index;
                }
                if (picker.ItemCount > 0) picker.Select(selectedIndex);
                picker.ItemSelected += index => Set("layer_id", picker.GetItemMetadata((int)index)); break;
            case "Solid Color": ColorField("Color", "color", Colors.White); break;
            case "Color Grade":
                Number("Exposure", "exposure", 0, -16, 16, .05); Number("Brightness", "brightness", 0, -2, 2, .01);
                Number("Contrast", "contrast", 1, 0, 4, .01); Number("Saturation", "saturation", 1, 0, 4, .01);
                _controls.curves(parent, node, workspace); break;
            case "Merge":
                var modes = new OptionButton(); foreach (string name in new[] { "Over", "Under", "In", "Out", "Atop", "Add", "Subtract", "Multiply", "Screen", "Difference", "Minimum", "Maximum" }) modes.AddItem(name);
                modes.Select(Value("mode", 0).AsInt32()); parent.AddChild(modes); modes.ItemSelected += value => Set("mode", (int)value);
                Number("Opacity", "opacity", 1, 0, 1, .01); break;
            case "Blur": Number("Radius", "radius", 2, 0, 32, 1, true); break;
            case "Mask": Note("Connect an RGBA image and an alpha mask."); break;
            case "Chroma Key":
                ColorField("Key color", "key_color", Colors.Green); Number("Tolerance", "tolerance", .2, 0, 2, .01);
                Number("Softness", "softness", .1, .001, 1, .01); Number("Spill", "spill", .5, 0, 1, .01); break;
            case "Luma Key":
                Number("Low threshold", "low", .1, 0, 1, .01); Number("High threshold", "high", .9, 0, 1, .01); Number("Softness", "softness", .05, .001, 1, .01);
                var invert = _controls.check(parent, "Invert matte", Value("invert", false).AsBool()); invert.Toggled += value => Set("invert", value); break;
            case "Depth Compare": Note("Depth comparison is not available in the preview evaluator yet."); break;
        }
        return true;
    }
}
