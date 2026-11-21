using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class CompositeLayerInspector : RefCounted
{
    private readonly CompositeInspectorControls _controls = new();
    private readonly CompositingDocument _rules = new();
    private readonly CompositeWorkspaceAnimation _animation = new();
    private static Variant Setting(Resource layer, string key, Variant fallback)
    { var settings = layer.Get("settings").AsGodotDictionary(); return settings.TryGetValue(key, out var found) ? found : fallback; }
    private static void SetSetting(Resource layer, string key, Variant value)
    { var settings = layer.Get("settings").AsGodotDictionary(); settings[key] = value; layer.Set("settings", settings); }

    public void build(Control parent, Resource document, Resource? layer, double time, Control workspace)
    {
        if (layer == null) { parent.AddChild(new Label { Text = "Select a layer to edit its source, blend, and timing.", AutowrapMode = TextServer.AutowrapMode.WordSmart }); return; }
        int kind = layer.Get("kind").AsInt32(); string id = layer.Get("id").AsString();
        string[] names = { "Image", "Solid", "Video", "CGI", "VFX", "Text", "Shape", "Mask", "Adjustment", "Group", "Linked Composition" };
        parent.AddChild(new Label { Text = "LAYER · " + (kind >= 0 && kind < names.Length ? names[kind] : "Unknown") });
        void Edit(string message, Action action)
        {
            var before = (Resource)document.Duplicate(true); action(); workspace.Call("_commit", message, before);
        }
        void Line(string caption, string value, string message, Action<string> apply)
        { var control = _controls.line(parent, caption, value); control.TextSubmitted += next => Edit(message, () => apply(next)); }
        void Number(string caption, double value, double minimum, double maximum, double step, string message, Action<double> apply)
        { var control = _controls.number(parent, caption, value, minimum, maximum, step); control.ValueChanged += next => Edit(message, () => apply(next)); }
        void Check(string caption, bool value, string message, Action<bool> apply)
        { var control = _controls.check(parent, caption, value); control.Toggled += next => Edit(message, () => apply(next)); }
        void ColorField(string caption, Color value, string message)
        { var control = _controls.color(parent, caption, value); control.ColorChanged += next => Edit(message, () => layer.Set("color", next)); }
        Variant Sample(string property) => _rules.sample_layer_value_resource(document, id, property, time, layer.Get(property));
        void Animated(string property, Variant value) => _animation.set_property(document, id, property, time, value);
        void VectorComponent(string property, bool x, double value)
        { var vector = Sample(property).AsVector2(); if (x) vector.X = (float)value; else vector.Y = (float)value; Animated(property, vector); }
        Line("Name", layer.Get("name").AsString(), "Rename layer", value => layer.Set("name", value));
        Check("Visible", layer.Get("visible").AsBool(), "Toggle visibility", value => layer.Set("visible", value));
        Check("Lock", layer.Get("locked").AsBool(), "Lock layer", value => layer.Set("locked", value));
        Number("Opacity", Sample("opacity").AsDouble(), 0, 1, .01, "Change opacity", value => Animated("opacity", value));
        var position = Sample("position").AsVector2(); var scale = Sample("scale").AsVector2();
        Number("X", position.X, -10000, 10000, 1, "Change position", value => VectorComponent("position", true, value));
        Number("Y", position.Y, -10000, 10000, 1, "Change position", value => VectorComponent("position", false, value));
        Number("Rotation", Mathf.RadToDeg(Sample("rotation").AsDouble()), -3600, 3600, 1, "Change rotation", value => Animated("rotation", Mathf.DegToRad(value)));
        Number("Scale X", scale.X, .01, 100, .01, "Change scale", value => VectorComponent("scale", true, value));
        Number("Scale Y", scale.Y, .01, 100, .01, "Change scale", value => VectorComponent("scale", false, value));
        parent.AddChild(new Label { Text = "ANIMATION · " + time.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) + " s" });
        var key = new Button { Text = "Set transform & opacity keys", TooltipText = "Key position, rotation, scale and opacity at the current playhead", CustomMinimumSize = new Vector2(0, 24) }; parent.AddChild(key);
        key.Pressed += () => Edit("Set transform and opacity keys", () => _animation.key_transform(document, id, time));
        var keyed = new List<string>(); foreach (string property in new[] { "position", "rotation", "scale", "opacity" }) if (_rules.has_layer_track_resource(document, id, property)) keyed.Add(char.ToUpperInvariant(property[0]) + property[1..]);
        parent.AddChild(new Label { Text = "Animated: " + (keyed.Count == 0 ? "None" : string.Join(", ", keyed)) });
        double start = layer.Get("start_time").AsDouble(), end = layer.Get("end_time").AsDouble(), duration = document.Get("duration").AsDouble();
        Number("Timeline start", start, 0, end >= 0 ? end : duration, .01, "Move layer in time", value => layer.Set("start_time", value));
        Number("Timeline end", end >= 0 ? end : duration, start, duration, .01, "Trim layer in time", value => layer.Set("end_time", value));
        if (kind == 1) ColorField("Color", layer.Get("color").AsColor(), "Change solid color");
        if (kind == 6)
        {
            string[] shapes = { "rectangle", "ellipse", "triangle", "polygon" }; var picker = new OptionButton(); foreach (string shape in shapes) picker.AddItem(char.ToUpperInvariant(shape[0]) + shape[1..]);
            picker.Select(Math.Max(0, System.Array.IndexOf(shapes, Setting(layer, "shape", "rectangle").AsString()))); parent.AddChild(picker);
            picker.ItemSelected += index => Edit("Change shape", () => SetSetting(layer, "shape", shapes[(int)index]));
            var size = Setting(layer, "size", new Vector2I(256, 256)).AsVector2I();
            void Resize(bool x, double value) { var current = Setting(layer, "size", new Vector2I(256, 256)).AsVector2I(); if (x) current.X = (int)value; else current.Y = (int)value; SetSetting(layer, "size", current); }
            Number("Width", size.X, 1, 4096, 1, "Resize shape", value => Resize(true, value)); Number("Height", size.Y, 1, 4096, 1, "Resize shape", value => Resize(false, value));
            ColorField("Fill", layer.Get("color").AsColor(), "Change shape color");
        }
        if (kind == 5)
        {
            Line("Text", Setting(layer, "text", "Text").AsString(), "Change text", value => SetSetting(layer, "text", value));
            Number("Font size", Setting(layer, "font_size", 72).AsDouble(), 1, 512, 1, "Change text size", value => SetSetting(layer, "font_size", (int)value));
            Line("Font resource path", Setting(layer, "font_path", "").AsString(), "Change text font", value => SetSetting(layer, "font_path", value));
            ColorField("Text color", layer.Get("color").AsColor(), "Change text color");
        }
        if (kind == 8)
        {
            foreach (var entry in new[] { ("Exposure", "exposure", -16.0, 16.0, .05), ("Brightness", "brightness", -2.0, 2.0, .01), ("Contrast", "contrast", 0.0, 4.0, .01), ("Saturation", "saturation", 0.0, 4.0, .01), ("Temperature", "temperature", -1.0, 1.0, .01), ("Tint", "tint", -1.0, 1.0, .01) })
                Number(entry.Item1, Setting(layer, entry.Item2, entry.Item2 is "contrast" or "saturation" ? 1.0 : 0.0).AsDouble(), entry.Item3, entry.Item4, entry.Item5, "Change adjustment", value => SetSetting(layer, entry.Item2, value));
            _controls.curves(parent, layer, workspace);
        }
        if (kind is 0 or 2) Line(kind == 2 ? "Video source" : "Source", layer.Get("source_path").AsString(), kind == 2 ? "Change video source" : "Change image source", value => layer.Set("source_path", value));
        if (kind == 2)
        {
            Number("Source offset", layer.Get("source_time_offset").AsDouble(), 0, 100000, .01, "Change video source offset", value => layer.Set("source_time_offset", value));
            Number("Playback speed", layer.Get("playback_speed").AsDouble(), .01, 100, .01, "Change video playback speed", value => layer.Set("playback_speed", value));
        }
        var blend = new OptionButton(); foreach (string name in new[] { "Over", "Under", "In", "Out", "Atop", "Add", "Subtract", "Multiply", "Screen", "Difference", "Minimum", "Maximum", "Crossfade" }) blend.AddItem(name);
        blend.Select(layer.Get("blend_mode").AsInt32()); parent.AddChild(blend); blend.ItemSelected += value => Edit("Change blend mode", () => layer.Set("blend_mode", (int)value));
    }
}
