using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

/// <summary>Native property widgets and curve edit transactions for the compositor.</summary>
public partial class CompositeInspectorControls : RefCounted
{
    public void curves(Control parent, Resource target, Control workspace)
    {
        var settings = target.Get("settings").AsGodotDictionary();
        var values = settings.TryGetValue("curves", out var initial) ? initial.AsGodotDictionary().Duplicate(true) : new Settings();
        parent.AddChild(new Label { Text = "CHANNEL CURVES" });
        var channels = new OptionButton(); foreach (string name in new[] { "Master", "Red", "Green", "Blue" }) channels.AddItem(name);
        parent.AddChild(channels); var editor = new CompositeCurveEditor(); parent.AddChild(editor);
        string[] names = { "master", "red", "green", "blue" }; int active = 0; Resource? before = null;
        void Load(int index)
        {
            active = index;
            editor.set_points(values.TryGetValue(names[index], out var points) ? points.AsGodotArray() : new Godot.Collections.Array());
        }
        channels.ItemSelected += index => Load((int)index); Load(0);
        editor.edit_started += () => before = (Resource)workspace.Get("document").As<Resource>().Duplicate(true);
        editor.points_changed += points =>
        {
            values[names[active]] = points; var currentSettings = target.Get("settings").AsGodotDictionary();
            currentSettings["curves"] = values.Duplicate(true); target.Set("settings", currentSettings);
            workspace.Get("evaluator").As<CompositingEvaluator>().clear_cache(); workspace.Call("_render");
        };
        editor.edit_finished += () =>
        {
            if (before == null) return;
            var snapshot = before; before = null;
            workspace.Call("_commit", "Edit " + char.ToUpperInvariant(names[active][0]) + names[active][1..] + " curve", snapshot);
        };
    }
    public LineEdit line(Control parent, string caption, string value)
    {
        var row = new VBoxContainer(); parent.AddChild(row);
        row.AddChild(new Label { Text = caption });
        var edit = new LineEdit { Text = value }; row.AddChild(edit);
        return edit;
    }
    public SpinBox number(Control parent, string caption, double value, double minimum, double maximum, double step)
    {
        var row = new HBoxContainer(); parent.AddChild(row);
        row.AddChild(new Label { Text = caption, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill });
        var spin = new SpinBox { MinValue = minimum, MaxValue = maximum, Step = step, Value = value, CustomMinimumSize = new Vector2(105, 0) };
        row.AddChild(spin); return spin;
    }
    public CheckButton check(Control parent, string caption, bool value)
    {
        var control = new CheckButton { Text = caption, ButtonPressed = value }; parent.AddChild(control);
        return control;
    }
    public ColorPickerButton color(Control parent, string caption, Color value)
    {
        var control = new ColorPickerButton { Text = caption, Color = value }; parent.AddChild(control);
        return control;
    }

}
