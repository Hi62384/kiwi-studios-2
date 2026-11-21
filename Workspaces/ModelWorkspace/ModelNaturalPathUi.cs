using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class ModelNaturalUi
{
    private readonly ModelModifiers _modifiers = new();
    private readonly ModelMeshOperations _meshes = new();
    public void open_path(Control workspace, string id)
    {
        var item = Component(workspace, id); if (item == null) return; var parameters = item.Get("parameters").AsGodotDictionary(); var points = (parameters.TryGetValue("growth_path", out var saved) ? saved.AsVector3Array() : new[] { Vector3.Zero, Vector3.Up * .5f, Vector3.Up }).ToList(); int selected = 0;
        if (points.Count == 0) points.Add(Vector3.Zero); if (points.Count == 1) points.Add(points[0] + Vector3.Up * .25f);
        var window = new Window { Title = "Vine path", Size = new Vector2I(370, 430), Transient = true }; workspace.AddChild(window); var column = new VBoxContainer(); column.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); window.AddChild(column); var list = new ItemList { SizeFlagsVertical = Control.SizeFlags.ExpandFill }; column.AddChild(list); var fields = new HBoxContainer(); column.AddChild(fields); var inputs = new List<Control>();
        void Refresh()
        {
            list.Clear(); for (int i = 0; i < points.Count; i++) list.AddItem(i + "   " + points[i]); selected = Mathf.Clamp(selected, 0, points.Count - 1); list.Select(selected); for (int axis = 0; axis < inputs.Count; axis++) inputs[axis].Call("set_value_no_signal", points[selected][axis]);
        }
        for (int axis = 0; axis < 3; axis++)
        {
            int component = axis; var box = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; fields.AddChild(box); box.AddChild(new Label { Text = new[] { "X", "Y", "Z" }[axis] }); var number = Number(box, -10000, 10000, .01, 0); inputs.Add(number);
            void Write(double value) { Vector3 point = points[selected]; point[component] = (float)value; points[selected] = point; Request(workspace, id, "growth_path", points.ToArray(), true); Refresh(); }
            number.Connect("value_changed", Callable.From<double>(Write)); number.Connect("drag_committed", Callable.From<double>(Write));
        }
        list.ItemSelected += index => { selected = (int)index; Refresh(); }; var row = new HBoxContainer(); column.AddChild(row);
        foreach (bool add in new[] { true, false })
        {
            var button = new Button { Text = add ? "＋ Point" : "− Point" }; row.AddChild(button); button.Pressed += () => { if (add) { points.Insert(selected + 1, points[selected] + Vector3.Up * .25f); selected++; } else if (points.Count > 2) points.RemoveAt(selected); Request(workspace, id, "growth_path", points.ToArray(), true); Refresh(); };
        }
        var attach = new Button { Text = "Attach to other selected mesh" }; column.AddChild(attach); attach.Pressed += () =>
        {
            var current = Component(workspace, id); if (current == null) return; var session = Session(workspace); var document = session.Get("document").As<Resource>(); var lookup = ModelDocumentOperations.Lookup(document);
            foreach (string otherId in session.Get("selected").AsGodotArray<string>())
            {
                if (otherId == id || !lookup.TryGetValue(otherId, out var other) || other.Get("mesh").As<Resource>() == null) continue;
                if (document.HasMethod("terrain") && document.Call("terrain", otherId).As<Resource>() != null) { workspace.Get("status").As<Label>().Text = "Bake this terrain to an editable model to use it as an attachment surface."; return; }
                var source = _meshes.copy_mesh(_modifiers.evaluate(other)); Transform3D pose = ModelDocumentOperations.WorldTransform(lookup, current).AffineInverse() * ModelDocumentOperations.WorldTransform(lookup, other); source.Set("vertices", source.Get("vertices").AsVector3Array().Select(vertex => pose * vertex).ToArray()); Request(workspace, id, "growth_surface", source, true); return;
            }
            workspace.Get("status").As<Label>().Text = "Select the vine and a surface mesh together first.";
        };
        var detach = new Button { Text = "Detach from surface" }; column.AddChild(detach); detach.Pressed += () => Request(workspace, id, "growth_surface", default, true); Refresh(); window.CloseRequested += window.QueueFree; window.PopupCentered();
    }
}
