using Godot;
using Settings = Godot.Collections.Dictionary;
public partial class ProjectFileInputOperations : RefCounted
{
    private readonly ProjectFileActionsOperations _actions = new();
    private readonly ProjectFileContextOperations _context = new();
    public void focused_input(Control owner)
    {
        if (!owner.IsVisibleInTree()) return; var focus = owner.GetViewport().GuiGetFocusOwner(); if (focus != null && (focus is LineEdit or TextEdit || !owner.GetParent().IsAncestorOf(focus))) return;
        var actions = owner.Get("file_system_callable_actions").As<Node>(); var context = owner.Get("file_system_extra_ui").As<Node>();
        if (Input.IsActionJustPressed("redo")) _actions.redo(actions); else if (Input.IsActionJustPressed("undo")) _actions.undo(actions); else if (Input.IsActionJustPressed("alternate_copy")) _context.copy_absolute_file_path(context); else if (Input.IsActionJustPressed("copy")) _context.copy_file_path(context); else if (Input.IsActionJustPressed("delete")) _context.show_delete_options(context); else if (Input.IsActionJustPressed("duplicate")) _context.duplicate_files(context); else if (Input.IsActionJustPressed("rename")) context.Call("rename_file");
    }
    public Variant drag_data(Button owner)
    {
        var paths = owner.Call("_native_drag_paths").AsStringArray(); if (paths.Length == 0) return default;
        var preview = new PanelContainer(); var label = new Label { Text = paths.Length == 1 ? paths[0].GetFile() : paths[0].GetFile() + "  +" + (paths.Length - 1) + " files" }; label.AddThemeColorOverride("font_color", new Color("eff7ff")); preview.AddChild(label); if (owner.GetViewport().GuiIsDragging()) owner.SetDragPreview(preview); else preview.Free(); return new Settings { ["type"] = "project_files", ["path"] = paths[0], ["paths"] = paths };
    }
}
