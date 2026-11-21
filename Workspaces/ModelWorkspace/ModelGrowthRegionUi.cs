using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceOperations
{
    private static bool GrowthScriptType(Resource value, string name)
    { var script = value.GetScript().As<Script>(); while (script != null) { if (script.ResourcePath == "res://Workspaces/ModelWorkspace/growth/" + name + ".gd") return true; script = script.GetBaseScript(); } return false; }
    private static string[] GrowthStyleNames() => KiwiGrowthStyle.presets().Keys.Select(value => value.AsString()).ToArray();
    private static Resource GrowthProperty(Settings? options = null)
    { var property = new ActorProperty(); property.Set("options", options ?? new Settings { ["extensions"] = new GArray { "tres", "res" } }); return property; }
    private async Task<string> GrowthPick(Control workspace, Resource property, string title)
    {
        var bridge = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>(); workspace.AddChild(bridge); bridge.Call("run", "pick_file", workspace, new GArray { property, title });
        var result = await ToSignal(bridge, "completed"); return result.Length > 0 && result[0].VariantType == Variant.Type.String ? result[0].AsString() : "";
    }
    private static bool GrowthCurrent(Control workspace, RefCounted session) => GodotObject.IsInstanceValid(workspace) && workspace.IsInsideTree() && Session(workspace) == session;
    private static void GrowthNotice(Control workspace, string text) => GrowthCanvas(workspace).EmitSignal("notice", text);
    private void GrowthColor(Control workspace, Node parent, string title, Color value, Action<Color> setter, string name = "")
    {
        Label(parent, title); var input = new ColorPickerButton { Name = name.Length > 0 ? name : "GrowthColor", Color = value, CustomMinimumSize = new Vector2(0, 24) }; parent.AddChild(input); Color before = value; var session = Session(workspace);
        input.PickerCreated += () => input.GetPicker().ColorMode = ColorPicker.ColorModeType.Rgb;
        input.ColorChanged += next => { if (GrowthCurrent(workspace, session)) setter(next); };
        input.PopupClosed += () => { if (!GrowthCurrent(workspace, session)) return; Color after = input.Color; setter(before); Action(session, "Growth " + title, () => setter(after)); before = after; };
    }
    public void growth_regions(Control workspace, Node parent, Resource data)
    {
        var toggle = new CheckButton { Name = "GrowthLocalAssignments", Text = "Local styles & materials", ButtonPressed = workspace.GetMeta("growth_regions_open", false).AsBool() }; parent.AddChild(toggle); toggle.Toggled += next => { workspace.SetMeta("growth_regions_open", next); workspace.Set("_refresh_pending", true); }; if (!toggle.ButtonPressed) return;
        var tool = GroomTool(workspace); var row = new HBoxContainer(); parent.AddChild(row); var scope = new OptionButton { FitToLongestItem = false, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; row.AddChild(scope);
        foreach (string title in new[] { "Selected strand", "Protected strands", "Selected guide", "Selected clump", "Selected strand's face", "Whole component" }) scope.AddItem(title);
        var session = Session(workspace); var regions = data.Get("regions").AsGodotArray();
        AddButton(row, "Assign", () =>
        {
            if (regions.Count >= 16) { GrowthNotice(workspace, "A growth component supports 16 local assignments."); return; }
            var roots = data.Get("roots").AsGodotArray(); Settings? selected = null; long selectedId = tool.Get("selected_root").AsInt64();
            foreach (var value in roots) { var candidate = value.AsGodotDictionary(); if (candidate["id"].AsInt64() == selectedId) { selected = candidate; break; } }
            string clump = selected != null ? GrowthValue(_growth.style(data, selected), "clump_id", "").AsString() : "", guide = tool.Get("selected_guide").AsString(); var chosen = new System.Collections.Generic.List<int>();
            _growthSettings.prepare_regions(data);
            foreach (var value in roots)
            {
                var root = value.AsGodotDictionary(); var edit = _growth.PreparedStyle(data, root);
                bool match = scope.Selected switch { 0 => root["id"].AsInt64() == selectedId, 1 => GrowthValue(edit, "locked", false).AsBool(), 2 => guide.Length > 0 && (GrowthValue(edit, "guide", "").AsString() == guide || GrowthValue(edit, "guide_weights", new Settings()).AsGodotDictionary().ContainsKey(guide)), 3 => clump.Length > 0 && GrowthValue(edit, "clump_id", "").AsString() == clump, 4 => selected != null && root["face"].AsInt64() == selected["face"].AsInt64(), 5 => true, _ => false };
                if (match) chosen.Add(root["id"].AsInt32());
            }
            if (chosen.Count == 0) { GrowthNotice(workspace, "Select a strand/guide or paint a protected region first."); return; }
            Action(session, "Assign local growth material", () => { regions.Add(new Settings { ["id"] = Guid.NewGuid().ToString("N"), ["name"] = scope.GetItemText(scope.Selected), ["roots"] = chosen.ToArray(), ["enabled"] = true, ["material"] = _growthMaterials.copy_material(data.Get("appearance").As<Resource>(), false), ["style"] = default(Variant) }); GrowthChanged(data); workspace.SetMeta("growth_region_index", regions.Count - 1); });
        });
        if (regions.Count == 0) return; var choose = new OptionButton { FitToLongestItem = false }; parent.AddChild(choose);
        foreach (var value in regions) { var region = value.AsGodotDictionary(); choose.AddItem(GrowthValue(region, "name", "Region").AsString() + " · " + GrowthValue(region, "roots", Array.Empty<int>()).AsInt32Array().Length); }
        int index = Math.Clamp(workspace.GetMeta("growth_region_index", 0).AsInt32(), 0, regions.Count - 1); choose.Select(index); choose.ItemSelected += next => { workspace.SetMeta("growth_region_index", next); workspace.Set("_refresh_pending", true); };
        var current = regions[index].AsGodotDictionary();
        bool RegionCurrent() => GrowthCurrent(workspace, session) && index < regions.Count && GrowthValue(regions[index].AsGodotDictionary(), "id", "").AsString() == GrowthValue(current, "id", "").AsString();
        var controls = new HFlowContainer(); parent.AddChild(controls); var enabled = new CheckBox { Text = "Enabled", ButtonPressed = GrowthValue(current, "enabled", true).AsBool() }; controls.AddChild(enabled); enabled.Toggled += next => Action(session, "Toggle growth assignment", () => { regions[index].AsGodotDictionary()["enabled"] = next; GrowthChanged(data); });
        foreach (int direction in new[] { -1, 1 }) { var move = AddButton(controls, direction < 0 ? "↑" : "↓", () => Action(session, "Reorder growth assignments", () => { var copy = regions[index]; regions.RemoveAt(index); regions.Insert(index + direction, copy); workspace.SetMeta("growth_region_index", index + direction); GrowthChanged(data); })); move.Disabled = index + direction < 0 || index + direction >= regions.Count; }
        AddButton(controls, "Remove", () => Action(session, "Remove local growth assignment", () => { regions.RemoveAt(index); GrowthChanged(data); })); Label(parent, "Later assignments win where regions overlap.");
        var material = GrowthValue(current, "material").As<Resource>();
        if (material != null)
        {
            foreach (string field in new[] { "root_color", "tip_color" }) GrowthColor(workspace, parent, field.Replace('_', ' ').Capitalize(), material.Get(field).AsColor(), next => material.Set(field, next));
            foreach (string field in new[] { "roughness", "specular", "opacity", "backlight" }) Number(workspace, parent, field.Capitalize(), material.Get(field).AsDouble(), 0, 1, .01, next => material.Set(field, next));
        }
        var assets = new HFlowContainer(); parent.AddChild(assets);
        AddButton(assets, "Load material…", async () =>
        {
            string path = await GrowthPick(workspace, GrowthProperty(), "Local growth material"); if (path.Length == 0 || !RegionCurrent()) return;
            Resource? loaded = path == "::empty-resource::" ? null : ResourceLoader.Load(path); if ((loaded == null && path != "::empty-resource::") || (loaded != null && !GrowthScriptType(loaded, "growth_material"))) { GrowthNotice(workspace, "Choose a Growth Material resource."); return; }
            Action(session, "Load local growth material", () => regions[index].AsGodotDictionary()["material"] = loaded != null ? _growthMaterials.copy_material(loaded, true) : default(Variant));
        });
        AddButton(assets, "Make unique", () => Action(session, "Unique local growth material", () => regions[index].AsGodotDictionary()["material"] = _growthMaterials.copy_material(material ?? data.Get("appearance").As<Resource>(), true)));
        AddButton(assets, "Use component", () => Action(session, "Inherit component material", () => regions[index].AsGodotDictionary()["material"] = default(Variant)));
        if (material != null) AddButton(assets, "Save material…", () => { var proxy = new KiwiSurfaceGrowthData(); proxy.Set("appearance", material); growth_save_material(workspace, proxy); });
        var styles = new OptionButton { FitToLongestItem = false }; parent.AddChild(styles); styles.AddItem("Inherit component style"); var localStyle = GrowthValue(current, "style").As<Resource>();
        foreach (string title in GrowthStyleNames()) { var preset = _growthMaterials.style_preset(title); styles.AddIconItem(_growthMaterials.texture(preset, null), title); if (localStyle?.Get("title").AsString() == title) styles.Select(styles.ItemCount - 1); }
        styles.ItemSelected += next => Action(session, "Local growth style", () => { regions[index].AsGodotDictionary()["style"] = next > 0 ? _growthMaterials.style_preset(styles.GetItemText((int)next)) : default(Variant); GrowthChanged(data); });
        if (localStyle != null)
        {
            foreach (string field in new[] { "length", "thickness", "curvature", "taper", "variation" })
                Number(workspace, parent, "Local " + field, GrowthValue(GrowthDict(localStyle, "values"), field, GrowthValue(_growthSettings.base_settings(data), field, 0)).AsDouble(), 0, 10, .001, next => { GrowthDict(localStyle, "values")[field] = next; GrowthChanged(data); });
            AddButton(parent, "Save local style…", () => { var proxy = new KiwiSurfaceGrowthData(); proxy.Set("growth_style", localStyle); growth_save_style(workspace, proxy); });
        }
        AddButton(parent, "Load local style…", async () =>
        {
            string path = await GrowthPick(workspace, GrowthProperty(), "Local growth style"); if (path.Length == 0 || !RegionCurrent()) return;
            Resource? loaded = path == "::empty-resource::" ? null : ResourceLoader.Load(path); if ((loaded == null && path != "::empty-resource::") || (loaded != null && !GrowthScriptType(loaded, "growth_style"))) { GrowthNotice(workspace, "Choose a Growth Style resource."); return; }
            Action(session, "Load local growth style", () => { regions[index].AsGodotDictionary()["style"] = loaded != null ? loaded.Duplicate(true) : default(Variant); GrowthChanged(data); });
        });
    }
}
