using Godot;
using System;
using System.Linq;
using GArray = Godot.Collections.Array;

public partial class ProjectFileSelectionOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private static GArray Selected(Node owner) => owner.Get("_selected_expandable_buttons").AsGodotArray();
    private static GArray Ordered(Node owner) => owner.Get("file_system").AsGodotObject().Get("_ordered_expandable_buttons").AsGodotArray();
    private static GArray Empty(Node owner) { var result = Selected(owner).Duplicate(); result.Clear(); return result; }
    private static Control? Button(Variant value) => value.VariantType == Variant.Type.Object && value.AsGodotObject() is Control button && GodotObject.IsInstanceValid(button) && !button.IsQueuedForDeletion() ? button : null;
    public void ready(Node owner)
    {
        var value = GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd").Get("node"); if (value.VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(value.AsGodotObject())) value.AsGodotObject().Connect("file_tree_recreated", new Callable(owner, "clear_selected"));
    }
    public void clear_selected(Node owner) => owner.Set("_selected_expandable_buttons", Empty(owner));
    public GArray get_selected_expandable_buttons(Node owner) => Selected(owner);
    public GArray top_selected_files(Node owner)
    {
        var result = Empty(owner); var selected = Selected(owner).Select(Button).Where(b => b != null).Cast<Control>().ToArray();
        var folders = selected.Where(b => DirAccess.DirExistsAbsolute(b.GetMeta("path").AsString())).ToArray();
        foreach (var button in selected) if (!folders.Any(folder => folder != button && _files.is_path_inside(folder.GetMeta("path").AsString(), button.GetMeta("path").AsString()))) result.Add(button);
        return result;
    }
    public GArray between(Node owner, Control? first, Control? last)
    {
        var result = Empty(owner); var ordered = Ordered(owner); int a = first == null ? -1 : ordered.IndexOf(first), b = last == null ? -1 : ordered.IndexOf(last);
        if (a < 0 || b < 0) { if (first != null && GodotObject.IsInstanceValid(first)) result.Add(first); return result; }
        for (int i = Math.Min(a, b); i <= Math.Max(a, b); i++) if (Button(ordered[i]) != null) result.Add(ordered[i]); return result;
    }
    public Control? extreme(Node owner, bool top)
    {
        Control? result = null; int best = top ? int.MaxValue : -1; var ordered = Ordered(owner);
        foreach (var value in Selected(owner)) { var button = Button(value); if (button == null) continue; int index = ordered.IndexOf(button); if (index >= 0 && (top ? index < best : index > best)) { best = index; result = button; } } return result;
    }
    public Control? shift_anchor(Node owner, Control button)
    {
        var top = extreme(owner, true); var bottom = extreme(owner, false); if (top == null || bottom == null) return null;
        var ordered = Ordered(owner); int a = ordered.IndexOf(top), b = ordered.IndexOf(bottom), reference = ordered.IndexOf(button);
        if (reference > a && reference > b) return top; if (reference < a && reference < b) return bottom; return Math.Abs(reference - b) <= Math.Abs(reference - a) ? bottom : top;
    }
    public bool is_selected(Node owner, Control button) => Selected(owner).Contains(button);
    private static void Cover(Control button, bool visible) => button.Call("get_cover_color_rect").As<Control>().Visible = visible;
    public void deselect(Node owner, GArray buttons)
    {
        foreach (var value in buttons.Duplicate()) { var button = Button(value); if (button != null) Cover(button, false); Selected(owner).Remove(value); }
    }
    public void select(Node owner, GArray buttons)
    {
        foreach (var value in buttons) { var button = Button(value); if (button == null) continue; Cover(button, true); if (!Selected(owner).Contains(button)) Selected(owner).Add(button); }
    }
    public void deselect_all(Node owner) => deselect(owner, Selected(owner));
    public void toggle(Node owner, GArray buttons)
    {
        foreach (var value in buttons.Duplicate()) { var button = Button(value); if (button == null) continue; if (is_selected(owner, button)) deselect(owner, new GArray { button }); else select(owner, new GArray { button }); }
    }
    public void right_clicked(Node owner, Control button)
    {
        if (is_selected(owner, button)) return; deselect_all(owner); select(owner, new GArray { button });
    }
    public void clicked(Node owner, Control button)
    {
        if (Input.IsActionPressed("ctrl")) toggle(owner, new GArray { button });
        else if (Input.IsActionPressed("shift")) { var anchor = shift_anchor(owner, button); deselect_all(owner); select(owner, between(owner, button, anchor)); }
        else { deselect_all(owner); select(owner, new GArray { button }); }
    }
}
