using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    public bool matches(string query, string label)
    { int at = 0; string text = label.ToLowerInvariant(); foreach (char letter in query.ToLowerInvariant()) { at = text.IndexOf(letter, at); if (at < 0) return false; at++; } return true; }
    private void Choice(Control workspace, string heading, IEnumerable<string> choices, Action<string> chosen, Action? release = null)
    {
        var labels = choices.ToArray(); var popup = new PopupPanel(); var style = new StyleBoxFlat { BgColor = new Color("13212d"), BorderColor = new Color("4b8e83"), ContentMarginLeft = 12, ContentMarginRight = 12, ContentMarginTop = 12, ContentMarginBottom = 12 }; style.SetBorderWidthAll(1); style.SetCornerRadiusAll(10); popup.AddThemeStyleboxOverride("panel", style); workspace.AddChild(popup);
        var column = new VBoxContainer { CustomMinimumSize = new Vector2(340, 0) }; popup.AddChild(column); workspace.Call("_label", column, heading); var search = new LineEdit { PlaceholderText = "Search…" }; column.AddChild(search); var scroll = new ScrollContainer { CustomMinimumSize = new Vector2(0, 330) }; column.AddChild(scroll); var list = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; scroll.AddChild(list);
        void Rebuild(string query)
        {
            foreach (Node child in list.GetChildren()) { list.RemoveChild(child); child.QueueFree(); }
            foreach (string label in labels) if (matches(query, label)) { var button = new Button { Text = label, CustomMinimumSize = new Vector2(0, 28) }; list.AddChild(button); button.Pressed += () => { popup.Hide(); chosen(label); }; }
        }
        search.TextChanged += Rebuild; Rebuild(""); popup.PopupHide += popup.QueueFree; if (release != null) popup.TreeExiting += release; popup.PopupCentered(new Vector2I(360, 420)); search.GrabFocus();
    }
    public void choice_menu(Control workspace, string heading, Godot.Collections.Array choices, RefCounted callback)
    { Choice(workspace, heading, choices.Select(value => value.AsString()), value => callback.Call("invoke", value), () => callback.Call("release")); }
    private static string[] Choices(Settings schema, string key) => schema[key].AsGodotArray().Select(value => value.AsString()).ToArray();
    public void create_menu(Control workspace)
    {
        var schema = workspace.Call("_command_choices").AsGodotDictionary(); var choices = Choices(schema, "shapes").ToList(); choices.AddRange(new[] { "Draw Box", "Draw Cylinder" }); choices.AddRange(new ModelNaturalSettings().kinds().Select(value => value.AsString())); choices.AddRange(new ModelNaturalCluster().kinds().Select(value => value.AsString())); choices.Add("Building"); choices.AddRange(GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").Call("kinds").AsGodotArray().Select(value => value.AsString()));
        var canvas = workspace.Get("canvas").As<Control>(); Choice(workspace, "CREATE GEOMETRY", choices, kind => { if (kind.StartsWith("Draw ", StringComparison.Ordinal)) canvas.Call("start_creation", kind[5..]); else Session(workspace).Call("add", kind, new Settings(), canvas.Get("target")); canvas.Call("request_sync"); canvas.GrabFocus(); });
    }
    public void deform_menu(Control workspace)
    { var canvas = workspace.Get("canvas").As<Control>(); Choice(workspace, "DEFORM BRUSH", new[] { "Grab", "Inflate", "Smooth", "Flatten", "Pinch", "Off" }, kind => { canvas.Set("sculpt", kind == "Off" ? "" : kind); workspace.Call("_refresh"); canvas.GrabFocus(); }); }
    public void command_search(Control workspace)
    {
        var schema = workspace.Call("_command_choices").AsGodotDictionary(); var commands = workspace.Get("_recent").AsGodotArray<string>().ToList(); foreach (string command in Choices(schema, "operations")) if (!commands.Contains(command)) commands.Add(command); commands.AddRange(Choices(schema, "shapes").Select(name => "Add " + name)); commands.AddRange(new[] { "Draw Box", "Draw Cylinder", "Quick Rig", "Draw Bones", "Rig Pose", "Weight Paint", "Bind Rig", "Rig Templates" }); commands.AddRange(Choices(schema, "modifiers").Select(name => "Modifier: " + name)); Choice(workspace, "MODELING COMMANDS", commands, command => workspace.Call("run_command", command));
    }
    public void run_command(Control workspace, string command)
    {
        if (command == "Search") { workspace.Call("command_search"); return; } var rig = workspace.Get("rig_ui").As<RefCounted>();
        switch (command) { case "Quick Rig": rig.Call("quick_rig"); return; case "Draw Bones": rig.Call("set_mode", "Draw"); return; case "Rig Pose": rig.Call("set_mode", "Pose"); return; case "Weight Paint": rig.Call("set_mode", "Weight"); return; case "Bind Rig": rig.Call("bind_async", rig.Get("method")); return; case "Rig Templates": rig.Call("templates"); return; }
        var session = Session(workspace); var canvas = workspace.Get("canvas").As<Control>();
        if (new[] { "Extrude", "Extrude individual", "Inset", "Bevel", "Subdivide", "Weld", "Smooth", "Flip normals", "Separate faces", "Join meshes", "Center origin", "Repeat operation" }.Contains(command) || command.StartsWith("Boolean ", StringComparison.Ordinal) || command.StartsWith("Modifier: ", StringComparison.Ordinal))
        { var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); foreach (string id in session.Get("selected").AsGodotArray<string>()) if (lookup.TryGetValue(id, out var item) && (item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null)) { Status(workspace, "Rigged mesh topology is preserved. Detach in Rigging before changing geometry."); return; } }
        var recent = workspace.Get("_recent").AsGodotArray<string>(); recent.Remove(command); recent.Insert(0, command); if (recent.Count > 8) recent.RemoveAt(recent.Count - 1);
        if (command.StartsWith("Add ", StringComparison.Ordinal)) session.Call("add", command[4..], new Settings(), canvas.Get("target"));
        else if (command.StartsWith("Draw ", StringComparison.Ordinal)) canvas.Call("start_creation", command[5..]);
        else if (command.StartsWith("Modifier: ", StringComparison.Ordinal)) { var item = session.Call("primary").As<Resource>(); if (item != null) Action(session, command, () => item.Get("modifiers").AsGodotArray().Add(new Settings { ["type"] = command[10..], ["enabled"] = true, ["amount"] = .2, ["axis"] = 0, ["count"] = 2 })); }
        else switch (command)
        {
            case "Extrude": case "Extrude individual": case "Inset": case "Bevel": case "Weld": workspace.Call("_operation_dialog", command); break;
            case "Subdivide": case "Smooth": case "Flip normals": Status(workspace, session.Call("edit_mesh", command, .3, false).AsString()); break;
            case "Duplicate": session.Call("duplicate_selected", false); break; case "Delete": Status(workspace, session.Call("delete_selected").AsString()); break; case "Parent": session.Call("parent_selected", false); break; case "Group": session.Call("group_selected"); break; case "Unparent": session.Call("parent_selected", true); break; case "Join meshes": session.Call("join_selected"); break; case "Separate faces": workspace.Call("_separate"); break; case "Center origin": workspace.Call("_center_origin"); break; case "Frame selected": canvas.Call("frame", false); break; case "Frame all": canvas.Call("frame", true); break;
            case "Repeat operation": Status(workspace, session.Call("edit_mesh", workspace.Get("_last_geometry"), workspace.Get("_last_amount"), false).AsString()); break;
            default: if (command.StartsWith("Boolean ", StringComparison.Ordinal)) workspace.Call("_boolean", command); else if (new[] { "Select all", "Invert selection", "Select connected", "Grow selection", "Shrink selection", "Select similar normals", "Select material" }.Contains(command)) workspace.Call("_selection", command); break;
        }
        workspace.Set("_refresh_pending", true); canvas.GrabFocus();
    }
}
