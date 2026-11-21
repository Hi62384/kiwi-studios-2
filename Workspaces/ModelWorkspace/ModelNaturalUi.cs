using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelNaturalUi : RefCounted
{
    private readonly ModelNaturalSettings _settings = new();
    private readonly ModelNaturalGenerator _generator = new();
    private static RefCounted Session(Control workspace) => workspace.Get("session").As<RefCounted>();
    private static Resource? Component(Control workspace, string id) => Session(workspace).Get("document").As<Resource>().Call("component", id).As<Resource>();
    private static Control Number(Node parent, double minimum, double maximum, double step, double value)
    { var number = new DragNumber(); number.Set("min_value", minimum); number.Set("max_value", maximum); number.Set("step", step); number.Call("set_value_no_signal", value); parent.AddChild(number); return number; }
    private static NaturalEditCoordinator? Controller(Control workspace, bool create)
    { var coordinator = workspace.GetNodeOrNull<NaturalEditCoordinator>("_NaturalEditCoordinator"); if (coordinator == null && create) { coordinator = new NaturalEditCoordinator { Name = "_NaturalEditCoordinator" }; workspace.AddChild(coordinator); coordinator.configure(workspace); } return coordinator; }
    private static void Request(Control workspace, string id, string key, Variant value, bool finished) => Controller(workspace, true)!.request(id, key, value, finished);
    private static void Finish(Control workspace) { var coordinator = Controller(workspace, false); if (coordinator != null) coordinator.finish(); else Session(workspace).Call("commit", "Change natural source"); }
    private static void Cancel(Control workspace) { var coordinator = Controller(workspace, false); if (coordinator != null) coordinator.cancel(); else Session(workspace).Call("cancel"); }
    public void properties(Control workspace, Resource item, Node parent)
    {
        string kind = item.Get("generator").AsString(), id = item.Get("id").AsString(); parent.AddChild(new Label { Text = "PROCEDURAL · " + kind }); var groups = new Dictionary<string, VBoxContainer>(); var document = Session(workspace).Get("document").As<Resource>(); var state = document.Get("workspace_state").AsGodotDictionary().TryGetValue("natural_folds", out var folds) ? folds.AsGodotDictionary() : new Settings();
        foreach (string name in new[] { "Form", "Branches & roots", "Foliage", "Detail" })
        {
            bool open = state.TryGetValue(id + name, out var saved) ? saved.AsBool() : name == "Form"; var button = new Button { Text = name, ToggleMode = true, ButtonPressed = open }; parent.AddChild(button); var content = new VBoxContainer { Visible = open }; parent.AddChild(content); groups[name] = content;
            button.Toggled += next => { content.Visible = next; state[id + name] = next; Session(workspace).Get("document").As<Resource>().Get("workspace_state").AsGodotDictionary()["natural_folds"] = state; };
        }
        var parameters = item.Get("parameters").AsGodotDictionary(); var defaults = _settings.defaults(kind);
        foreach (var (key, minimum, maximum, step) in new[] { ("seed", 0.0, 2147483647.0, 1.0), ("height", .02, 200.0, .05), ("radius", .005, 30.0, .01), ("branches", 1.0, 16.0, 1.0), ("levels", 0.0, 3.0, 1.0), ("length", .05, 1.5, .01), ("angle", .1, 2.0, .01), ("curve", 0.0, 1.0, .01), ("droop", 0.0, 1.0, .01), ("lean", -1.0, 1.0, .01), ("taper", .1, .98, .01), ("foliage", 0.0, 3.0, .1), ("leaf_size", .01, 2.0, .01), ("roots", 0.0, 16.0, 1.0), ("irregularity", 0.0, .8, .01), ("detail", 6.0, 32.0, 1.0) })
        {
            if (kind.StartsWith("Rock", StringComparison.Ordinal) && !new[] { "seed", "height", "radius", "irregularity", "detail" }.Contains(key)) continue;
            if (kind.StartsWith("Plant", StringComparison.Ordinal) && kind != "Plant / Bush" && !new[] { "seed", "height", "radius", "branches" }.Contains(key)) continue;
            if (kind.StartsWith("Prop", StringComparison.Ordinal) && !new[] { "seed", "height", "radius", "curve", "detail" }.Contains(key)) continue;
            string section = new[] { "seed", "height", "radius" }.Contains(key) ? "Form" : new[] { "foliage", "leaf_size" }.Contains(key) ? "Foliage" : new[] { "detail", "irregularity" }.Contains(key) ? "Detail" : "Branches & roots";
            var row = new HBoxContainer(); groups[section].AddChild(row); row.AddChild(new Label { Text = key.Capitalize(), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }); var number = Number(row, minimum, kind == "Plant / Cactus" && key == "branches" ? 5 : maximum, step, parameters.TryGetValue(key, out var value) ? value.AsDouble() : defaults[key].AsDouble()); number.CustomMinimumSize = new Vector2(95, 0);
            number.Connect("interaction_started", new Callable(Session(workspace), "begin")); number.Connect("preview_changed", Callable.From<double>(value => Request(workspace, id, key, value, false))); number.Connect("drag_committed", Callable.From<double>(_ => Finish(workspace))); number.Connect("drag_cancelled", Callable.From(() => Cancel(workspace))); number.Connect("value_changed", Callable.From<double>(value => { if (!number.Get("dragging").AsBool()) Request(workspace, id, key, value, true); }));
        }
        var bake = new Button { Text = "Make editable mesh" }; parent.AddChild(bake); bake.Pressed += () => { var session = Session(workspace); session.Call("begin"); var current = Component(workspace, id); current?.Set("generator", ""); session.Call("commit", "Make natural mesh editable"); };
        if (kind == "Plant / Vine") { var path = new Button { Text = "Edit growth path / attachment…" }; parent.AddChild(path); path.Pressed += () => open_path(workspace, id); }
        var materials = item.Get("surface_materials").AsGodotArray();
        if (!kind.StartsWith("Rock", StringComparison.Ordinal) && materials.Count > 1 && materials[1].As<Material>() is ShaderMaterial)
        {
            var season = new OptionButton(); parent.AddChild(season); foreach (string name in new[] { "Summer foliage", "Spring foliage", "Autumn foliage", "Winter foliage" }) season.AddItem(name); season.Select(Mathf.Clamp(parameters.TryGetValue("season", out var seasonValue) ? seasonValue.AsInt32() : 0, 0, 3)); season.ItemSelected += index => appearance(workspace, id, "season", index);
            var row = new HBoxContainer(); parent.AddChild(row); row.AddChild(new Label { Text = "Wind" }); var wind = Number(row, 0, 1, .01, parameters.TryGetValue("wind_strength", out var windValue) ? windValue.AsDouble() : 0); wind.Connect("value_changed", Callable.From<double>(value => appearance(workspace, id, "wind_strength", value))); wind.Connect("drag_committed", Callable.From<double>(value => appearance(workspace, id, "wind_strength", value)));
        }
        if (kind.StartsWith("Tree", StringComparison.Ordinal)) { var edit = new Button { Text = "Edit individual branches…" }; parent.AddChild(edit); edit.Pressed += () => branches(workspace, id); var reset = new Button { Text = "Reset branch edits" }; parent.AddChild(reset); reset.Pressed += () => Request(workspace, id, "branch_overrides", new Settings(), true); }
    }
    public void appearance(Control workspace, string id, string key, Variant value)
    {
        var session = Session(workspace); session.Call("begin"); var item = Component(workspace, id); if (item != null)
        {
            var materials = item.Get("surface_materials").AsGodotArray(); if (materials.Count >= 2) { item.Get("parameters").AsGodotDictionary()[key] = value; if (materials[1].As<Material>()?.Duplicate(false) is ShaderMaterial material) { if (key == "wind_strength") material.SetShaderParameter(key, value); else material.SetShaderParameter("leaf_color", new[] { new Color(.14f, .38f, .055f), new Color(.45f, .65f, .12f), new Color(.72f, .22f, .025f), new Color(.52f, .43f, .24f) }[Mathf.Clamp(value.AsInt32(), 0, 3)]); materials[1] = material; } }
        }
        session.Call("commit", "Change natural " + key);
    }
    public void branches(Control workspace, string id)
    {
        var item = Component(workspace, id); if (item == null) return; var data = _generator.Generate(item.Get("generator").AsString(), item.Get("parameters").AsGodotDictionary(), () => false); var popup = new Window { Title = "Branch structure", Size = new Vector2I(340, 420), Transient = true }; workspace.AddChild(popup); var column = new VBoxContainer(); column.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); popup.AddChild(column); var picker = new OptionButton(); column.AddChild(picker); var identities = new List<string>();
        foreach (var branch in data["branches"].AsGodotArray<Settings>()) { string identity = branch["id"].AsString(); if (identity == "trunk") continue; identities.Add(identity); picker.AddItem(identity); }
        var fields = new VBoxContainer(); column.AddChild(fields);
        void Update()
        {
            foreach (Node child in fields.GetChildren()) child.QueueFree(); if (picker.Selected < 0) return; string identity = identities[picker.Selected]; var current = Component(workspace, id); if (current == null) return; var parameters = current.Get("parameters").AsGodotDictionary(); var overrides = parameters.TryGetValue("branch_overrides", out var saved) ? saved.AsGodotDictionary() : new Settings(); var value = overrides.TryGetValue(identity, out var edit) ? edit.AsGodotDictionary() : new Settings();
            foreach (var (title, key, minimum, maximum) in new[] { ("Length", "length", .05, 3.0), ("Thickness", "radius", .1, 2.0), ("Rotate X", "rx", -180.0, 180.0), ("Rotate Y", "ry", -180.0, 180.0), ("Rotate Z", "rz", -180.0, 180.0) })
            {
                bool scalar = key == "length" || key == "radius"; Vector3 rotation = value.TryGetValue("rotation", out var r) ? r.AsVector3() : Vector3.Zero; double initial = scalar ? value.TryGetValue(key, out var numberValue) ? numberValue.AsDouble() : 1 : rotation[Array.IndexOf(new[] { "rx", "ry", "rz" }, key)]; var row = new HBoxContainer(); fields.AddChild(row); row.AddChild(new Label { Text = title, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }); var number = Number(row, minimum, maximum, scalar ? .01 : 1, initial); number.Connect("value_changed", Callable.From<double>(next => change_branch(workspace, id, identity, key, next))); number.Connect("drag_committed", Callable.From<double>(next => change_branch(workspace, id, identity, key, next)));
            }
            var reset = new Button { Text = "Reset this branch" }; fields.AddChild(reset); reset.Pressed += () => change_branch(workspace, id, identity, "reset", true); var prune = new Button { Text = "Prune branch and its twigs" }; fields.AddChild(prune); prune.Pressed += () => change_branch(workspace, id, identity, "pruned", true);
        }
        picker.ItemSelected += _ => Update(); Update(); popup.CloseRequested += popup.QueueFree; popup.PopupCentered();
    }
    public void change_branch(Control workspace, string id, string identity, string key, Variant value)
    {
        var target = Component(workspace, id); if (target == null) return; var pending = workspace.GetMeta("natural_edit", new Settings()).AsGodotDictionary(); var parameters = pending.TryGetValue("id", out var pendingId) && pendingId.AsString() == id ? pending["parameters"].AsGodotDictionary() : target.Get("parameters").AsGodotDictionary(); var overrides = parameters.TryGetValue("branch_overrides", out var all) ? all.AsGodotDictionary().Duplicate(true) : new Settings(); var edit = overrides.TryGetValue(identity, out var current) ? current.AsGodotDictionary() : new Settings();
        if (key == "length" || key == "radius" || key == "pruned") edit[key] = value; else if (key != "reset") { Vector3 rotation = edit.TryGetValue("rotation", out var r) ? r.AsVector3() : Vector3.Zero; rotation[Array.IndexOf(new[] { "rx", "ry", "rz" }, key)] = value.AsSingle(); edit["rotation"] = rotation; }
        if (key == "reset") overrides.Remove(identity); else overrides[identity] = edit; Request(workspace, id, "branch_overrides", overrides, true);
    }
}
