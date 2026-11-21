using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthPhysicsOperations
{
    public void open(GodotObject editor, GodotObject actor, Node owner)
    {
        var prototype = Get(Dict(editor.Get("physics").AsGodotObject(), "prototypes"), actor.Get("id"), new Settings()).AsGodotDictionary(); if (!prototype.ContainsKey("growth")) return;
        var popup = new AcceptDialog { Title = "Growth motion corrections", Name = "GrowthMotionCorrections" }; owner.AddChild(popup); var column = new VBoxContainer(); popup.AddChild(column);
        column.AddChild(new Label { Text = "Animation-only corrections. Changed contacts require a new simulation.", AutowrapMode = TextServer.AutowrapMode.WordSmart });
        var list = new ItemList { SelectMode = ItemList.SelectModeEnum.Multi, CustomMinimumSize = new Vector2(420, 120) }; column.AddChild(list);
        foreach (var row in prototype["growth"].AsGodotDictionary()["controls"].AsGodotArray()) { string id = row.AsGodotDictionary()["id"].AsString(); list.AddItem(id); list.SetItemMetadata(list.ItemCount - 1, id); } if (list.ItemCount > 0) list.Select(0);
        GArray Chosen() => new(list.GetSelectedItems().Select(index => Variant.From(list.GetItemMetadata(index).AsString())));
        var scroll = new ScrollContainer { CustomMinimumSize = new Vector2(420, 330) }; column.AddChild(scroll); var fields = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; scroll.AddChild(fields);
        var animation = GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs"); var authoring = GD.Load<GDScript>("res://scripts/actors/physics/destruction/destruction_authoring.gd");
        bool Current() => GodotObject.IsInstanceValid(editor) && editor.Get("model").AsGodotObject().Call("actor_for_id", actor.Get("id")).AsGodotObject() == actor;
        void Rebuild()
        {
            foreach (Node child in fields.GetChildren()) { fields.RemoveChild(child); child.QueueFree(); } var ids = Chosen(); if (ids.Count == 0 || !Current()) return;
            var sampled = animation.Call("sampled_values", actor, actor.Get("animation_time")).AsGodotDictionary(); var values = Get(Get(sampled, "growth_overrides", new Settings()).AsGodotDictionary(), ids[0], new Settings()).AsGodotDictionary();
            foreach (var (field, title, fallback, minimum, maximum) in new (string, string, Variant, double, double)[] {
                ("from", "From (source s)", 0.0, 0, 86400), ("to", "Until (-1 = end)", -1.0, -1, 86400), ("blend", "Boundary blend (s)", .1, 0, 10),
                ("influence", "Correction strength", 1.0, 0, 1), ("time_scale", "Time scale", 1.0, 0, 10), ("time_offset", "Time offset (scene s)", 0.0, -86400, 86400),
                ("freeze_time", "Freeze at scene s (-1 = off)", -1.0, -1, 86400), ("offset", "Root-local offset", Vector3.Zero, -100, 100), ("rotation", "Root-local rotation", Vector3.Zero, -360, 360) })
            {
                fields.AddChild(new Label { Text = title }); var line = new HBoxContainer(); fields.AddChild(line); Variant current = Get(values, field, fallback); bool vector = current.VariantType == Variant.Type.Vector3;
                for (int axis = 0; axis < (vector ? 3 : 1); axis++)
                {
                    int at = axis; var input = new DragNumber(); input.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; input.MinValue = minimum; input.MaxValue = maximum; input.Step = .01; input.SetValueNoSignal(vector ? current.AsVector3()[at] : current.AsDouble()); line.AddChild(input);
                    Variant Convert(double value)
                    {
                        if (!vector) return value; var selected = Chosen(); Vector3 result = selected.Count > 0 ? animation.Call("sampled_value", actor, new[] { "growth_overrides", selected[0].AsString(), field }, actor.Get("animation_time"), current).AsVector3() : current.AsVector3(); result[at] = (float)value; return result;
                    }
                    void Edit(double value) { if (Current()) authoring.Call("edit_fragments", editor.Get("model"), actor, new StringName("growth_overrides"), Chosen(), field, Convert(value)); }
                    input.ValueChanged += value => { if (!input.Get("dragging").AsBool()) Edit(value); }; input.Connect("drag_committed", Callable.From<double>(Edit));
                }
                var key = new Button { Text = "◇", TooltipText = "Keyframe selected guides" }; line.AddChild(key); key.Pressed += () => { if (Current()) authoring.Call("key_fragments", editor.Get("model"), actor, new StringName("growth_overrides"), Chosen(), field, fallback); };
            }
        }
        list.MultiSelected += (_, _) => Rebuild(); Rebuild(); popup.Confirmed += popup.QueueFree; popup.Canceled += popup.QueueFree; popup.PopupCentered(new Vector2I(470, 540));
    }
}
