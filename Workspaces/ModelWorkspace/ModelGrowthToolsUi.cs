using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    public void growth_build_presets(Control workspace, Node parent, Resource data)
    {
        var tool = GroomTool(workspace); var row = new HBoxContainer(); parent.AddChild(row); var presets = new OptionButton { FitToLongestItem = false, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; row.AddChild(presets); presets.AddItem("Brush presets"); var saved = data.Get("brush_presets").AsGodotArray();
        foreach (var value in saved) { var preset = value.AsGodotDictionary(); string name = preset["tool"].AsString(); presets.AddIconItem(growth_icon(name), name + " · " + Mathf.Snapped(preset["radius"].AsDouble(), .01).ToString(System.Globalization.CultureInfo.InvariantCulture)); }
        int selected = tool.Get("selected_preset").AsInt32(); if (selected >= 0 && selected < saved.Count) presets.Select(selected + 1);
        presets.ItemSelected += index =>
        {
            if (index == 0) { tool.Set("selected_preset", -1); return; } tool.Set("selected_preset", index - 1);
            foreach (var pair in saved[(int)index - 1].AsGodotDictionary()) tool.Set(pair.Key.AsStringName(), pair.Value); workspace.Set("_refresh_pending", true);
        };
        var session = Session(workspace);
        foreach (bool fresh in new[] { false, true }) AddButton(row, fresh ? "+" : "Save", () =>
        {
            var preset = new Settings(); foreach (string field in new[] { "tool", "radius", "strength", "falloff", "spacing", "value", "frequency", "symmetry", "through", "replace", "target_cut", "paint_color", "clump_start", "clump_end", "clump_variation" }) preset[field] = tool.Get(field);
            Action(session, "Save groom brush preset", () =>
            {
                int at = tool.Get("selected_preset").AsInt32(); if (fresh || at < 0 || at >= saved.Count) { if (saved.Count < 32) { saved.Add(preset); tool.Set("selected_preset", saved.Count - 1); } } else saved[at] = preset;
            });
        });
        if (selected >= 0 && selected < saved.Count) AddButton(row, "×", () => Action(session, "Delete groom brush preset", () => { saved.RemoveAt(tool.Get("selected_preset").AsInt32()); tool.Set("selected_preset", -1); }));
    }
    public void growth_build_individual(Control workspace, Node parent, Resource data)
    {
        var tool = GroomTool(workspace); Settings? root = null;
        foreach (var value in data.Get("roots").AsGodotArray()) { var candidate = value.AsGodotDictionary(); if (candidate["id"].AsInt64() == tool.Get("selected_root").AsInt64()) { root = candidate; break; } }
        if (root == null) { Label(parent, "Click a strand root to edit it."); return; }
        string id = root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture); Label(parent, "STRAND " + id); var values = _growth.style(data, root); var basis = _growthSettings.base_settings(data);
        Settings Individual() { var all = GrowthDict(data, "individual"); if (!all.ContainsKey(id)) all[id] = new Settings(); return all[id].AsGodotDictionary(); }
        foreach (var (field, title, fallback, minimum, maximum) in new[] {
            ("length", "Length", values["length"].AsDouble(), 0.0, 100.0), ("thickness", "Thickness", GrowthValue(basis, "thickness", .01).AsDouble(), .0001, 2.0),
            ("width", "Feather width", GrowthValue(basis, "width", .14).AsDouble(), .0001, 10.0), ("curl", "Curl", 0.0, -4.0, 4.0), ("roll", "Roll (degrees)", 0.0, -180.0, 180.0), ("frizz", "Frizz", 0.0, 0.0, 2.0) })
            Number(workspace, parent, title, GrowthValue(values, field, fallback).AsDouble(), minimum, maximum, .001, next => { Individual()[field] = next; GrowthChanged(data); });
        foreach (string field in new[] { "direction", "offset" }) for (int axis = 0; axis < 3; axis++)
        {
            int at = axis; Vector3 fallback = field == "direction" ? Vector3.Up : Vector3.Zero, initial = GrowthValue(values, field, fallback).AsVector3();
            Number(workspace, parent, field.Capitalize() + " " + "XYZ"[at], initial[at], -10, 10, .01, next => { var own = Individual(); Vector3 vector = GrowthValue(own, field, GrowthValue(values, field, fallback)).AsVector3(); vector[at] = (float)next; own[field] = vector; GrowthChanged(data); });
        }
        var session = Session(workspace); AddButton(parent, "Reset selected strand", () => Action(session, "Reset strand", () => { GrowthDict(data, "individual").Remove(id); GrowthChanged(data); }));
    }
    public void growth_build_guides(Control workspace, Node parent, Resource data)
    {
        var tool = GroomTool(workspace); Label(parent, "Click root → guide · Drag gold handles"); var choose = new OptionButton { FitToLongestItem = false }; parent.AddChild(choose); var guides = GrowthDict(data, "guides");
        foreach (var pair in guides) { string id = pair.Key.AsString(); choose.AddItem("Guide " + (choose.ItemCount + 1)); choose.SetItemMetadata(choose.ItemCount - 1, id); if (id == tool.Get("selected_guide").AsString()) choose.Select(choose.ItemCount - 1); }
        choose.ItemSelected += index => { tool.Set("selected_guide", choose.GetItemMetadata((int)index).AsString()); workspace.Set("_refresh_pending", true); };
        string selected = tool.Get("selected_guide").AsString(); if (!guides.TryGetValue(selected, out var value)) return; var guide = value.AsGodotDictionary(); var session = Session(workspace);
        var locked = new CheckButton { Text = "Lock guide handles", ButtonPressed = GrowthValue(guide, "locked", false).AsBool() }; parent.AddChild(locked); locked.Toggled += next => Action(session, "Lock groom guide", () => guides[selected].AsGodotDictionary()["locked"] = next);
        void Field(string key, string title, double minimum, double maximum, double fallback) => Number(workspace, parent, title, GrowthValue(guide, key, fallback).AsDouble(), minimum, maximum, .01, next => { guides[selected].AsGodotDictionary()[key] = next; GrowthChanged(data); });
        Field("length_scale", "Guide length", .01, 10, 1);
        for (int axis = 0; axis < 3; axis++)
        {
            int at = axis; Number(workspace, parent, "Guide rotation " + "XYZ"[at], Mathf.RadToDeg(GrowthValue(guide, "rotation", Vector3.Zero).AsVector3()[at]), -360, 360, 1, next => { var own = guides[selected].AsGodotDictionary(); Vector3 rotation = GrowthValue(own, "rotation", Vector3.Zero).AsVector3(); rotation[at] = Mathf.DegToRad((float)next); own["rotation"] = rotation; GrowthChanged(data); });
        }
        Field("influence", "Guide influence", 0, 1, 1); var row = new HFlowContainer(); parent.AddChild(row);
        foreach (string action in new[] { "Add point", "Remove tip", "Smooth guide", "Duplicate guide", "Remove guide" }) AddButton(row, action, () => Action(session, action, () =>
        {
            var own = guides[selected].AsGodotDictionary(); var points = own["points"].AsVector3Array().ToList();
            if (action == "Add point") points.Add(points[^1] + (points[^1] - points[^2]) * .5f);
            else if (action == "Remove tip" && points.Count > 2) points.RemoveAt(points.Count - 1);
            else if (action == "Smooth guide") for (int i = 1; i < points.Count - 1; i++) points[i] = points[i] * .5f + (points[i - 1] + points[i + 1]) * .25f;
            else if (action == "Duplicate guide") guides[Guid.NewGuid().ToString("N")] = own.Duplicate(true);
            if (action == "Remove guide") guides.Remove(selected); else own["points"] = points.ToArray(); GrowthChanged(data);
        }));
    }
}
