using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    private static T Service<T>(string name) where T : RefCounted => (T)Engine.GetSingleton("KiwiNativeServices").Call("service", name).As<RefCounted>();
    private static void Clear(Node parent) { foreach (Node child in parent.GetChildren()) { parent.RemoveChild(child); child.QueueFree(); } }
    private static void Label(Node parent, string text) { var label = new Godot.Label { Text = text }; label.AddThemeColorOverride("font_color", new Color("7ddcc4")); parent.AddChild(label); }
    public void changed(Control workspace)
    {
        var canvas = workspace.Get("canvas").As<Control>(); canvas.Call("request_sync"); if (canvas.Get("_drag").AsBool()) workspace.Call("_sync_transform_fields");
        if (!workspace.Get("_property_gesture").AsBool() && !canvas.Get("_drag").AsBool() && canvas.Get("_create_phase").AsInt32() == 0 && !canvas.Get("_pressed").AsBool()) workspace.Set("_refresh_pending", true); workspace.EmitSignal("document_changed");
    }
    public void process(Control workspace)
    {
        var rig = workspace.Get("canvas").As<Control>().Get("rig_tool").As<RefCounted>(); if (rig != null && rig.Get("drag").AsString().Length > 0) return;
        if (workspace.Get("_refresh_pending").AsBool() && workspace.IsVisibleInTree()) { workspace.Set("_refresh_pending", false); workspace.Call("_refresh"); }
    }
    public void refresh(Control workspace)
    {
        if (!workspace.IsInsideTree()) return; workspace.Set("_syncing", true);
        try
        {
            var session = Session(workspace); var canvas = workspace.Get("canvas").As<Control>(); var context = workspace.Get("context").As<Node>(); var properties = workspace.Get("properties").As<Node>(); var modeButtons = workspace.Get("mode_buttons").AsGodotDictionary(); var toolButtons = workspace.Get("_tool_buttons").AsGodotDictionary(); var tabs = workspace.Get("_inspector_tabs").As<TabContainer>(); string path = workspace.Get("path").AsString(), mode = session.Get("mode").AsString(), sculpt = canvas.Get("sculpt").AsString();
            workspace.Get("title").As<Label>().Text = "3D MODEL  /  " + (path.Length > 0 ? path.GetFile() : "Untitled"); foreach (Variant key in modeButtons.Keys) modeButtons[key].As<Button>().SetPressedNoSignal(mode == key.AsString()); foreach (Variant key in toolButtons.Keys) toolButtons[key].As<Button>().SetPressedNoSignal(canvas.Get("tool").AsString() == key.AsString() && sculpt.Length == 0); workspace.Get("_snap_button").As<CheckButton>().SetPressedNoSignal(canvas.Get("snap").AsBool()); var space = workspace.Get("_space_picker").As<OptionButton>(); space.Select(canvas.Get("local_axes").AsBool() ? 1 : 0);
            workspace.Call("_rebuild_tree"); Clear(context); Clear(properties); Clear(workspace.Get("_modifiers").As<Node>()); Clear(workspace.Get("_surfaces").As<Node>()); var transformFields = workspace.Get("_transform_fields").AsGodotDictionary(); transformFields.Clear();
            var item = session.Call("primary").As<Resource>(); var rig = canvas.Get("rig_tool").As<RefCounted>(); var editor = rig?.Get("editor").As<RefCounted>(); bool rigging = editor != null && editor.Get("enabled").AsBool(); foreach (Variant value in modeButtons.Values) value.As<Control>().Visible = !rigging; foreach (Variant value in toolButtons.Values) value.As<Control>().Visible = !rigging || editor!.Get("mode").AsString() == "Pose" || editor.Get("mode").AsString() == "Weight"; space.Visible = !rigging; tabs.SetTabTitle(0, rigging ? "Rig" : "Object"); tabs.SetTabHidden(1, rigging); tabs.SetTabHidden(2, rigging); if (rigging) tabs.CurrentTab = 0;
            if (rigging) { var ui = workspace.Get("rig_ui").As<RefCounted>(); ui.Call("build_context", context); ui.Call("build_properties", properties); return; }
            AddButton(context, mode == "Face" ? "Extrude" : "Edit ▾", () => { if (Session(workspace).Get("mode").AsString() == "Face") workspace.Call("run_command", "Extrude"); else workspace.Call("command_search"); });
            if (mode == "Face") { var push = AddButton(context, "Push/pull", () => { canvas.Set("push_pull", !canvas.Get("push_pull").AsBool()); canvas.GrabFocus(); }); push.ToggleMode = true; push.ButtonPressed = canvas.Get("push_pull").AsBool(); push.TooltipText = "Drag faces to extrude/recess · Alt+drag also works"; foreach (string name in new[] { "Inset", "Bevel", "Separate faces" }) AddButton(context, name, () => workspace.Call("run_command", name)); }
            else foreach (string name in mode == "Edge" ? new[] { "Bevel", "Subdivide", "Weld" } : new[] { "Duplicate", "Group", "Parent", "Unparent" }) AddButton(context, name, () => workspace.Call("run_command", name));
            AddButton(context, "Deform ▾", () => workspace.Call("_deform_menu")); var proportional = new CheckButton { Text = "Proportional", ButtonPressed = canvas.Get("proportional").AsBool() }; context.AddChild(proportional); proportional.Toggled += next => { canvas.Set("proportional", next); workspace.Set("_refresh_pending", true); };
            if (canvas.Get("proportional").AsBool() || sculpt.Length > 0) { Number(workspace, context, "Radius", canvas.Get("radius").AsDouble(), .02, 100, .05, value => canvas.Set("radius", value)); if (sculpt.Length > 0) Number(workspace, context, "Strength", canvas.Get("strength").AsDouble(), .01, 1, .01, value => canvas.Set("strength", value)); }
            if (item == null) { Label(properties, "Start with a shape"); AddButton(properties, "＋ Create geometry", () => workspace.Call("create_menu")); Label(properties, "Or open an existing model"); AddButton(properties, "Open / import…", () => workspace.Call("open_dialog")); return; }
            string id = item.Get("id").AsString(), generator = item.Get("generator").AsString(); var mesh = item.Get("mesh").As<Resource>(); Label(properties, item.Get("title").AsString()); GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").Call("properties", workspace, item, properties);
            if (item.Get("growth").As<Resource>() != null) { growth_build(workspace, item, (VBoxContainer)properties); return; }
            if (mesh != null)
            {
                AddButton(context, "Surface growth…", () => growth_add_menu(workspace)); BuildStructure(workspace, item, properties);
            }
            if (item.Get("locked").AsBool()) Label(properties, "Locked — unlock in Components"); var affine = _documents.transform_values(item.Get("transform").AsTransform3D());
            foreach (var (name, key) in new[] { ("Position", "position"), ("Rotation", "rotation"), ("Scale", "scale") })
            {
                Vector3 vector = affine[key].AsVector3(); Label(properties, name); var row = new HBoxContainer(); properties.AddChild(row); for (int i = 0; i < 3; i++) { int axis = i; var control = Number(workspace, row, new[] { "X", "Y", "Z" }[i], vector[i], -10000, 10000, .01, value => transform_value(workspace, value, name, axis)); control.CustomMinimumSize = new Vector2(62, 0); control.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; transformFields[name + i] = control; }
            }
            if (Service<ModelNaturalCluster>("natural_cluster").accepts(item)) Service<ModelNaturalCluster>("natural_cluster").properties(workspace, item, properties);
            else if (ModelNaturalSettings.Accepts(generator)) Service<ModelNaturalUi>("natural_ui").properties(workspace, item, properties);
            else if (generator.Length > 0 && item.Get("skin_mesh").As<Mesh>() == null && item.Get("binding").As<Resource>() == null)
            {
                Label(properties, "PARAMETRIC · " + generator); var fields = (new[] { "Box", "Beam", "Panel", "Plane", "Prism", "Stairs" }.Contains(generator) ? new[] { "width", "height", "depth" } : new[] { "radius", "height", "segments" }).ToList(); if (generator == "Sphere" || generator == "Torus") fields = new() { "radius", "segments" }; if (generator == "Plane") fields = new() { "width", "depth" }; if (generator == "Arch") fields.Add("inner_ratio"); if (generator == "Gear") fields.AddRange(new[] { "teeth", "tooth_depth", "hole" }); if (generator == "Pipe") fields.Add("hole"); if (generator == "Stairs") fields.Add("steps"); var parameters = item.Get("parameters").AsGodotDictionary(); bool dimensions = fields[0] == "width";
                foreach (string field in fields) { Vector3 size = parameters.TryGetValue("size", out var saved) ? saved.AsVector3() : Vector3.One; double value = parameters.TryGetValue(field, out var found) ? found.AsDouble() : field == "segments" ? 24 : field == "teeth" ? 16 : field == "steps" ? 6 : .5; int axis = Array.IndexOf(new[] { "width", "height", "depth" }, field); if (dimensions && axis >= 0) value = size[axis]; bool integer = field == "segments" || field == "teeth" || field == "steps"; Number(workspace, properties, field.Capitalize(), value, .001, integer ? 128 : 100, integer ? 1 : .01, next => parameter_value(workspace, next, id, field, dimensions)); }
                AddButton(properties, "Make editable mesh", () => { var current = Item(workspace, id); if (current != null) Action(Session(workspace), "Make editable", () => current.Set("generator", "")); });
            }
            properties.AddChild(new Label { Text = mesh != null ? mesh.Call("_vertex_count").AsInt32() + " vertices · " + mesh.Get("faces").AsGodotArray().Count + " faces" : item.Get("is_skeleton").AsBool() ? "Skeleton · " + item.Get("bones").AsGodotArray().Count + " bones" : "Group / transform" }); if (item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null) Label(properties, "Rigged mesh · topology preserved\nQuick Rig → Pose / Weight to edit"); Label(properties, "PRECISION"); Number(workspace, properties, "Grid", canvas.Get("grid_step").AsDouble(), .01, 100, .01, value => { canvas.Set("grid_step", value); canvas.Call("rebuild_grid"); });
            var snap = new OptionButton(); foreach (string name in new[] { "Grid", "Vertex", "Edge", "Surface", "Origin" }) snap.AddItem(name); snap.Select(Array.IndexOf(new[] { "Grid", "Vertex", "Edge", "Surface", "Origin" }, canvas.Get("snap_kind").AsString())); properties.AddChild(snap); snap.ItemSelected += index => { canvas.Set("snap_kind", snap.GetItemText((int)index)); workspace.Set("_refresh_pending", true); }; if (canvas.Get("snap_kind").AsString() == "Surface") { var align = new CheckButton { Text = "Align to surface normal", ButtonPressed = canvas.Get("align_surface").AsBool() }; properties.AddChild(align); align.Toggled += next => canvas.Set("align_surface", next); }
            AddButton(properties, "Center origin", () => workspace.Call("run_command", "Center origin")); AddButton(properties, "Frame selected", () => canvas.Call("frame", false)); workspace.Call("_build_modifiers", item); workspace.Call("_build_surfaces", item);
        }
        finally { workspace.Set("_syncing", false); }
    }
    private void BuildStructure(Control workspace, Resource item, Node properties)
    {
        var definition = GD.Load<GDScript>("res://scripts/actors/physics/structure/structure_definition.gd"); var role = new OptionButton { FitToLongestItem = false, TooltipText = "Structural role when this model is added to a scene. Scene Structure controls edit strength, pivots and timed failures. Parenting does not weld components." }; role.AddItem("Structure: off"); foreach (Variant name in definition.GetScriptConstantMap()["ROLES"].AsGodotArray()) role.AddItem(name.AsString()); var data = item.Get("structural").AsGodotDictionary(); var enabledKey = new StringName("structure_enabled"); var roleKey = new StringName("structure_role"); var connectionsKey = new StringName("structure_connections"); role.Select(data.TryGetValue(enabledKey, out var enabled) && enabled.AsBool() ? (data.TryGetValue(roleKey, out var saved) ? saved.AsInt32() : 0) + 1 : 0); properties.AddChild(role); string id = item.Get("id").AsString();
        role.ItemSelected += index => { var current = Item(workspace, id); if (current != null) Action(Session(workspace), "Structural support role", () => { var structural = current.Get("structural").AsGodotDictionary(); structural[enabledKey] = index > 0; structural[roleKey] = Math.Max(0, index - 1); }); };
        AddButton(properties, "Connect selected components", () =>
        {
            var session = Session(workspace); string[] ids = session.Get("selected").AsGodotArray<string>().ToArray(); if (ids.Length < 2) return;
            Action(session, "Connect model structure", () => { var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); if (!lookup.TryGetValue(ids[0], out var first)) return; foreach (string otherId in ids.Skip(1)) { if (!lookup.TryGetValue(otherId, out var other) || first.Get("mesh").As<Resource>() == null || other.Get("mesh").As<Resource>() == null) continue; Transform3D a = ModelDocumentOperations.WorldTransform(lookup, first), b = ModelDocumentOperations.WorldTransform(lookup, other); Vector3 point = (a.Origin + b.Origin) * .5f; var structural = first.Get("structural").AsGodotDictionary(); structural[enabledKey] = true; other.Get("structural").AsGodotDictionary()[enabledKey] = true; var connections = structural.TryGetValue(connectionsKey, out var found) ? found.AsGodotDictionary() : new Settings(); structural[connectionsKey] = connections; connections[Guid.NewGuid().ToString("N")] = definition.Call("connection", otherId, a.AffineInverse() * point, b.AffineInverse() * point, 0); } });
        });
    }
}
