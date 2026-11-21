using Godot;
using System;
using System.Collections.Generic;

public partial class ModelWorkspaceOperations
{
    public void rebuild_tree(Control workspace)
    {
        var session = Session(workspace); var hierarchy = workspace.Get("hierarchy").As<ModelHierarchy>(); hierarchy.session = session; hierarchy.Clear(); var root = hierarchy.CreateItem(); var rows = new Dictionary<string, TreeItem>(); var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); var selected = session.Get("selected").AsGodotArray<string>();
        foreach (var item in lookup.Values)
        {
            string id = item.Get("id").AsString(); var row = hierarchy.CreateItem(root); row.SetText(0, item.Get("title").AsString()); row.SetMetadata(0, id); row.SetEditable(0, true); var growth = item.Get("growth").As<Resource>(); Texture2D icon;
            if (growth != null) { var settings = growth.Get("settings").AsGodotDictionary(); int type = settings.TryGetValue("type", out var value) ? value.AsInt32() : 0; icon = growth_icon(new[] { "Hair", "Fur", "Feathers" }[Math.Clamp(type, 0, 2)]); }
            else icon = GD.Load<Texture2D>("res://resources/Images/ActorIcons/" + (item.Get("is_skeleton").AsBool() ? "SkeletonRig" : item.Get("mesh").As<Resource>() != null ? "BasicMesh" : "Point3D") + ".svg");
            row.SetIcon(0, icon); row.SetIconMaxWidth(0, 18); bool visible = item.Get("visible").AsBool(); row.SetText(1, visible ? "●" : "○"); row.SetTooltipText(1, "Hide / show component"); row.SetText(2, item.Get("locked").AsBool() ? "L" : "·"); row.SetSelectable(1, false); row.SetSelectable(2, false); rows[id] = row; if (!visible) row.SetCustomColor(0, new Color("667f90")); if (selected.Contains(id)) row.Select(0);
        }
        foreach (var item in lookup.Values) { string parent = item.Get("parent_id").AsString(), id = item.Get("id").AsString(); if (rows.TryGetValue(parent, out var parentRow) && !ModelDocumentOperations.Descendant(lookup, parent, id)) { var row = rows[id]; root.RemoveChild(row); parentRow.AddChild(row); } }
        var input = new Callable(workspace, "_tree_input"); if (!hierarchy.IsConnected(Control.SignalName.GuiInput, input)) hierarchy.Connect(Control.SignalName.GuiInput, input);
    }
    public void tree_input(Control workspace, InputEvent input)
    {
        if (input is not InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } mouse) return; var hierarchy = workspace.Get("hierarchy").As<Tree>(); var row = hierarchy.GetItemAtPosition(mouse.Position); if (row == null) return; int column = hierarchy.GetColumnAtPosition(mouse.Position); var item = Item(workspace, row.GetMetadata(0).AsString()); if ((column != 1 && column != 2) || item == null) return;
        Action(Session(workspace), "Toggle component state", () => { string field = column == 1 ? "visible" : "locked"; item.Set(field, !item.Get(field).AsBool()); });
    }
    public void tree_button(Control workspace, TreeItem row)
    { var item = Item(workspace, row.GetMetadata(0).AsString()); if (item != null) Action(Session(workspace), "Toggle visibility", () => item.Set("visible", !item.Get("visible").AsBool())); }
    public void tree_selected(Control workspace, TreeItem row, int column, bool selectedRow)
    {
        if (workspace.Get("_syncing").AsBool()) return; var session = Session(workspace); var selected = session.Get("selected").AsGodotArray<string>(); string primary = selectedRow ? row.GetMetadata(0).AsString() : selected.Count > 0 ? selected[^1] : ""; selected.Clear(); var hierarchy = workspace.Get("hierarchy").As<Tree>(); TreeItem? current = hierarchy.GetNextSelected(null);
        while (current != null) { selected.Add(current.GetMetadata(0).AsString()); current = hierarchy.GetNextSelected(current); } if (selected.Remove(primary)) selected.Add(primary);
        var rig = workspace.Get("canvas").As<Control>().Get("rig_tool").As<RefCounted>(); var item = session.Call("primary").As<Resource>(); if (rig != null && item != null && item.Get("is_skeleton").AsBool()) rig.Get("editor").As<RefCounted>().Set("rig_id", item.Get("id")); session.Set("elements", Array.Empty<int>()); session.EmitSignal("changed");
    }
    public void rename(Control workspace)
    { var row = workspace.Get("hierarchy").As<Tree>().GetEdited(); if (row == null) return; var item = Item(workspace, row.GetMetadata(0).AsString()); if (item != null) Action(Session(workspace), "Rename component", () => item.Set("title", row.GetText(0))); }
}
