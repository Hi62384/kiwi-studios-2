using Godot;
using System;
using System.IO;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    public void growth_name_field(Control workspace, Node parent, Resource resource)
    {
        var input = new LineEdit { Text = resource.Get("title").AsString(), PlaceholderText = "Preset name", TooltipText = "Saved presets appear in project files, where they can also be renamed or deleted.", SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; parent.AddChild(input); var session = Session(workspace);
        void Commit() { if (!GrowthCurrent(workspace, session)) return; string title = input.Text.Trim(); if (title.Length > 64) title = title[..64]; if (title.Length > 0 && title != resource.Get("title").AsString()) Action(session, "Rename growth preset", () => resource.Set("title", title)); }
        input.TextSubmitted += _ => Commit(); input.FocusExited += Commit;
    }
    private static string GrowthRoot() => GD.Load<GDScript>("res://scripts/actors/core/actor_project_file_picker.gd").Call("root_directory").AsString();
    private static bool GrowthInside(string path) => GD.Load<GDScript>("res://scripts/Globals/file_operations.gd").Call("is_path_inside", GrowthRoot(), path).AsBool();
    private void GrowthSaveResource(Control workspace, Resource resource, bool style)
    {
        string name = resource.Get("title").AsString(); foreach (char c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_'); if (name.Length == 0) name = "Growth material";
        var dialog = new FileDialog { Title = style ? "Save growth style" : "Save growth material", FileMode = FileDialog.FileModeEnum.SaveFile, Access = FileDialog.AccessEnum.Filesystem, CurrentDir = GrowthRoot(), CurrentFile = name + ".tres", Filters = new[] { style ? "*.tres ; Growth style" : "*.tres ; Growth material" } }; workspace.AddChild(dialog);
        dialog.FileSelected += path =>
        {
            if (!GrowthInside(path)) { GrowthNotice(workspace, "Choose a location inside the project."); return; }
            Error error = ResourceSaver.Save(resource, path); GrowthNotice(workspace, error == Error.Ok ? style ? "Style saved." : "Material saved." : style ? "Could not save style." : "Could not save material."); dialog.QueueFree();
            if (error == Error.Ok) GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").Call("refresh_filesystem");
        };
        dialog.Canceled += dialog.QueueFree; dialog.PopupCentered(new Vector2I(700, 500));
    }
    public void growth_save_style(Control workspace, Resource data) => GrowthSaveResource(workspace, data.Get("growth_style").As<Resource>(), true);
    public void growth_save_material(Control workspace, Resource data) => GrowthSaveResource(workspace, data.Get("appearance").As<Resource>(), false);
    public async void growth_load_style(Control workspace, Resource data)
    {
        var session = Session(workspace); string path = await GrowthPick(workspace, GrowthProperty(), "Load growth style"); if (path.Length == 0 || path == "::empty-resource::" || !GrowthCurrent(workspace, session)) return;
        var loaded = ResourceLoader.Load(path); if (loaded == null || !GrowthScriptType(loaded, "growth_style")) { GrowthNotice(workspace, "Choose a Growth Style resource."); return; }
        Action(session, "Load growth style", () => { data.Set("growth_style", loaded.Duplicate(true)); GrowthChanged(data); });
    }
    public void growth_styles(Control workspace, Node parent, Resource data)
    {
        Label(parent, "GROWTH STYLE"); var presets = new OptionButton { Name = "GrowthStylePreset", FitToLongestItem = false }; parent.AddChild(presets); presets.AddItem("Choose a style…"); var names = GrowthStyleNames();
        foreach (string title in names) { var preset = _growthMaterials.style_preset(title); presets.AddIconItem(_growthMaterials.texture(preset, null), title); }
        var session = Session(workspace); presets.ItemSelected += index => { if (index > 0) Action(session, "Apply growth style", () => { data.Set("growth_style", _growthMaterials.style_preset(presets.GetItemText((int)index))); GrowthChanged(data); }); };
        var style = data.Get("growth_style").As<Resource>(); if (style == null) { AddButton(parent, "Load style…", () => growth_load_style(workspace, data)); return; }
        Label(parent, style.Get("title").AsString()); growth_name_field(workspace, parent, style);
        foreach (var (field, title, minimum, maximum, step) in new[] { ("thickness", "Root thickness", .0001, 2.0, .001), ("tip_thickness", "Tip thickness (-1 = taper)", -1.0, 2.0, .001), ("taper", "Taper", 0.0, 1.0, .01), ("twist", "Twist", -12.0, 12.0, .01), ("frizz", "Frizz", 0.0, 2.0, .01), ("frizz_frequency", "Frizz frequency", .1, 24.0, .1), ("flatten", "Cross-section depth", .05, 1.0, .01), ("feather_asymmetry", "Vane asymmetry", -.8, .8, .01) })
            Number(workspace, parent, title, GrowthValue(_growthSettings.base_settings(data), field, field == "flatten" ? 1.0 : field == "tip_thickness" ? -1.0 : 0.0).AsDouble(), minimum, maximum, step, next => { GrowthDict(style, "values")[field] = next; GrowthChanged(data); });
        var shape = new OptionButton { FitToLongestItem = false }; parent.AddChild(shape); foreach (string title in new[] { "Ribbon", "Card lock", "Rounded strand", "Tube" }) shape.AddItem(title); shape.Select(GrowthValue(GrowthDict(style, "values"), "cross_section", 0).AsInt32());
        shape.ItemSelected += index => Action(session, "Growth cross-section", () => { GrowthDict(style, "values")["cross_section"] = index; GrowthChanged(data); }); var row = new HFlowContainer(); parent.AddChild(row);
        AddButton(row, "Clear style", () => Action(session, "Clear growth style", () => { data.Set("growth_style", default(Variant)); GrowthChanged(data); })); AddButton(row, "Save style…", () => growth_save_style(workspace, data));
        AddButton(row, "Duplicate", () => Action(session, "Duplicate growth style", () => { var copy = style.Duplicate(true); copy.Set("asset_id", Guid.NewGuid().ToString("N")); copy.Set("title", copy.Get("title").AsString() + " copy"); data.Set("growth_style", copy); }));
        if (Array.IndexOf(names, style.Get("title").AsString()) >= 0) AddButton(row, "Reset preset", () => Action(session, "Reset growth style preset", () => { data.Set("growth_style", _growthMaterials.style_preset(style.Get("title").AsString())); GrowthChanged(data); })); AddButton(row, "Load style…", () => growth_load_style(workspace, data));
    }
}
