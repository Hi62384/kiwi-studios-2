using Godot;
using System;
using System.Linq;

public partial class ModelWorkspaceOperations
{
    private readonly ModelDocumentOperations _documents = new();
    private readonly ModelPrimitives _primitives = new();
    private Control Number(Control workspace, Node parent, string label, double value, double minimum, double maximum, double step, Action<double> setter, Action? release = null)
    {
        var row = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; parent.AddChild(row); var caption = new Label { Text = label }; caption.AddThemeFontSizeOverride("font_size", 11); row.AddChild(caption);
        var number = new DragNumber(); number.MinValue = minimum; number.MaxValue = maximum; number.Step = step; number.Value = value; row.AddChild(number); var session = Session(workspace); bool began = false, closed = false;
        bool Current() => !closed && GodotObject.IsInstanceValid(workspace) && workspace.IsInsideTree() && Session(workspace) == session;
        void Finish(bool cancel)
        {
            if (cancel && began) session.Call("cancel"); else if (!cancel && Current()) session.Call("commit", "Change " + label); began = false;
            if (Current()) { workspace.Set("_property_gesture", false); workspace.Set("_refresh_pending", true); }
        }
        number.Connect("interaction_started", Callable.From(() => { if (!Current()) return; session.Call("begin"); began = true; workspace.Set("_property_gesture", true); }));
        number.Connect("preview_changed", Callable.From<double>(next => { if (!Current()) return; setter(next); session.EmitSignal("changed"); }));
        number.Connect("drag_committed", Callable.From<double>(_ => Finish(false))); number.Connect("drag_cancelled", Callable.From(() => Finish(true)));
        number.ValueChanged += next => { if (!Current() || workspace.Get("_syncing").AsBool() || number.Get("dragging").AsBool()) return; Action(session, "Change " + label, () => setter(next)); };
        number.TreeExiting += () => { if (began) Finish(true); closed = true; release?.Invoke(); }; return number;
    }
    public Control number(Control workspace, Node parent, string label, double value, double minimum, double maximum, double step, RefCounted setter)
    { return Number(workspace, parent, label, value, minimum, maximum, step, next => setter.Call("invoke", next), () => setter.Call("release")); }
    public void sync_transform_fields(Control workspace)
    {
        var item = Session(workspace).Call("primary").As<Resource>(); if (item == null) return; var affine = _documents.transform_values(item.Get("transform").AsTransform3D()); var fields = workspace.Get("_transform_fields").AsGodotDictionary();
        foreach (var (kind, key) in new[] { ("Position", "position"), ("Rotation", "rotation"), ("Scale", "scale") })
        {
            Vector3 value = affine[key].AsVector3(); for (int i = 0; i < 3; i++) if (fields.TryGetValue(kind + i, out var saved) && saved.As<SpinBox>() is SpinBox control && GodotObject.IsInstanceValid(control) && !control.Get("dragging").AsBool() && !control.GetLineEdit().HasFocus()) control.SetValueNoSignal(value[i]);
        }
    }
    public void transform_value(Control workspace, double value, string kind, int axis)
    {
        var session = Session(workspace); var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
        foreach (string id in session.Get("selected").AsGodotArray<string>())
        {
            if (!lookup.TryGetValue(id, out var item) || item.Get("locked").AsBool()) continue; if (item.Get("binding").As<Resource>() != null) { Status(workspace, "Move the armature or its parent. Detach before editing bound component rest transforms."); continue; }
            Transform3D transform = item.Get("transform").AsTransform3D(); if (kind == "Position") transform.Origin[axis] = (float)value;
            else { var affine = _documents.transform_values(transform); Vector3 angles = affine["rotation"].AsVector3() * Mathf.Pi / 180, scale = affine["scale"].AsVector3(); if (kind == "Rotation") angles[axis] = Mathf.DegToRad((float)value); else scale[axis] = Mathf.Abs((float)value) > .0001f ? (float)value : .0001f; transform.Basis = Basis.FromEuler(angles) * Basis.FromScale(scale) * affine["model_basis_residual"].AsBasis(); }
            item.Set("transform", transform);
        }
    }
    public void parameter_value(Control workspace, double value, string id, string field, bool dimensions)
    {
        var session = Session(workspace); var item = session.Get("document").As<Resource>().Call("component", id).As<Resource>(); if (item == null || item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null) return; var parameters = item.Get("parameters").AsGodotDictionary(); int axis = Array.IndexOf(new[] { "width", "height", "depth" }, field);
        if (dimensions && axis >= 0) { Vector3 size = parameters.TryGetValue("size", out var saved) ? saved.AsVector3() : Vector3.One; size[axis] = (float)value; parameters["size"] = size; } else parameters[field] = value;
        item.Set("mesh", _primitives.create(item.Get("generator").AsString(), parameters)); if (session.Call("primary").As<Resource>() == item) session.Set("elements", Array.Empty<int>());
    }
}
