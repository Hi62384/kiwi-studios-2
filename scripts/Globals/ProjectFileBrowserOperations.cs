using Godot;
using System;
using System.Linq;
using Array = Godot.Collections.Array;

public partial class ProjectFileBrowserOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private static GDScript Files => GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd");
    private static GodotObject Field(Control owner, string name) => owner.Get(name).AsGodotObject();
    private static Array List(Control owner, string name) => owner.Get(name).AsGodotArray();
    private static string PathOf(GodotObject file) => file.Get("path").AsString();
    private static bool Folder(GodotObject file) => file.GetPropertyList().Any(p => p["name"].AsString() == "contains");
    private static Button Main(Control button) => button.Call("get_main_button").As<Button>();
    public void ready(Control owner)
    {
        Files.Get("node").AsGodotObject().Connect("file_tree_recreated", new Callable(owner, "update_filesystem_display"));
        Field(owner, "file_search_line_edit").Connect("text_changed", new Callable(owner, "_search_changed"));
        Field(owner, "undo_button").Connect("pressed", new Callable(Field(owner, "file_system_callable_actions"), "undo"));
        Field(owner, "redo_button").Connect("pressed", new Callable(Field(owner, "file_system_callable_actions"), "redo"));
    }
    public bool should_filter(Control owner) => Field(owner, "file_search_line_edit").Get("text").AsString() != "";
    public void collect_filtered(Control owner, GodotObject file)
    {
        if (PathOf(file).GetFile().Contains(Field(owner, "file_search_line_edit").Get("text").AsString())) List(owner, "_filtered_files_to_display").Add(PathOf(file));
        if (Folder(file)) foreach (var child in file.Get("contains").AsGodotArray()) collect_filtered(owner, child.AsGodotObject());
    }
    public bool should_display(Control owner, string path)
    {
        if (!should_filter(owner)) return true;
        if (path.GetFile().Contains(Field(owner, "file_search_line_edit").Get("text").AsString()))
        {
            List(owner, "_filtered_files_to_display").Remove(path);
            return true;
        }
        return path.GetExtension() == "" && List(owner, "_filtered_files_to_display").Any(p => _files.is_path_inside(path, p.AsString()));
    }
    private static Control NewButton() => GD.Load<PackedScene>("uid://basy0qkxblg2m").Instantiate<Control>();
    private static Texture2D Icon(bool folder) => GD.Load<Texture2D>(folder ? "uid://h5xgw3ns54ys" : "uid://mwmlqweqemfk");
    public void update_display(Control owner)
    {
        owner.Set("_display_generation", owner.Get("_display_generation").AsInt64() + 1);
        Field(owner, "files_selector").Call("clear_selected");
        var container = (Control)Field(owner, "container");
        foreach (Node child in container.GetChildren()) { container.RemoveChild(child); child.QueueFree(); }
        var expanded = List(owner, "_expanded_folders").Duplicate();
        var rootValue = Files.Get("root_folder");
        if (rootValue.VariantType != Variant.Type.Object || rootValue.AsGodotObject() == null) return;
        var root = rootValue.AsGodotObject();
        List(owner, "_filtered_files_to_display").Clear();
        if (should_filter(owner)) collect_filtered(owner, root);
        List(owner, "_ordered_expandable_buttons").Clear();
        var button = NewButton();
        List(owner, "_ordered_expandable_buttons").Add(button);
        container.AddChild(button);
        style(owner, button, PathOf(root).GetFile(), Icon(true), true);
        owner.Call("_load_button_thumbnail", PathOf(root), button, owner.Get("_display_generation"));
        update_folder(owner, root, button);
        var notDisplayed = List(owner, "_expanded_folders").Duplicate();
        List(owner, "_expanded_folders").Clear();
        foreach (var path in expanded) if (!notDisplayed.Contains(path)) List(owner, "_expanded_folders").Add(path);
    }
    public void update_folder(Control owner, GodotObject folder, Control button)
    {
        setup_folder(owner, folder, button);
        foreach (var value in folder.Get("contains").AsGodotArray())
        {
            var file = value.AsGodotObject(); string path = PathOf(file);
            if (!should_display(owner, path)) continue;
            bool isFolder = Folder(file);
            var child = NewButton();
            List(owner, "_ordered_expandable_buttons").Add(child);
            button.Call("add_child_in_expand", child);
            style(owner, child, path.GetFile(), Icon(isFolder), isFolder);
            owner.Call("_load_button_thumbnail", path, child, owner.Get("_display_generation"));
            if (isFolder) update_folder(owner, file, child); else setup_file(owner, file, child);
        }
    }
    public void apply_thumbnail(Control owner, Variant value, Texture2D? thumbnail, long generation)
    {
        if (generation != owner.Get("_display_generation").AsInt64() || value.VariantType != Variant.Type.Object) return;
        var button = value.AsGodotObject() as Node;
        if (!GodotObject.IsInstanceValid(button) || button!.IsQueuedForDeletion() || thumbnail == null) return;
        button.Set("icon", thumbnail);
    }
    private static void ConnectButton(Control owner, Control button, string path, bool folder)
    {
        var main = Main(button);
        var mover = Field(owner, "file_mover");
        main.Connect("mouse_entered", Callable.From(() => { if (GodotObject.IsInstanceValid(mover)) mover.Call("set_hovered_expandable_button", button); }));
        main.Connect("mouse_exited", Callable.From(() => { if (GodotObject.IsInstanceValid(mover)) mover.Call("set_hovered_expandable_button", default(Variant)); }));
        main.Connect("pressed", Callable.From(() => { if (GodotObject.IsInstanceValid(owner)) owner.Call("file_pressed", button); }));
        main.Connect("gui_input", Callable.From<InputEvent>(input => { if (GodotObject.IsInstanceValid(owner)) owner.Call("_file_button_input", input, button, path, folder); }));
    }
    public void setup_folder(Control owner, GodotObject folder, Control button)
    {
        string path = PathOf(folder); button.SetMeta("path", path);
        Main(button).Set("accepts_drop", Callable.From<Variant, bool>(data => GodotObject.IsInstanceValid(owner) && can_drop(owner, data, path)));
        Main(button).Set("receives_drop", Callable.From<Variant>(data => { if (GodotObject.IsInstanceValid(owner)) drop(owner, data, path); }));
        var expanded = List(owner, "_expanded_folders");
        if (expanded.Contains(path)) { button.Set("expanded", true); expanded.Remove(path); }
        button.Connect("toggled", Callable.From<bool>(on => { if (GodotObject.IsInstanceValid(owner)) toggled(owner, path, on); }));
        ConnectButton(owner, button, path, true);
    }
    public void setup_file(Control owner, GodotObject file, Control button)
    {
        string path = PathOf(file); button.SetMeta("path", path);
        Main(button).Set("drag_paths_provider", Callable.From<string[]>(() => GodotObject.IsInstanceValid(owner) ? dragged_paths(owner, button) : System.Array.Empty<string>()));
        ConnectButton(owner, button, path, false);
    }
    public void button_input(Control owner, InputEvent input, Control button, string path, bool folder)
    {
        if (input is not InputEventMouseButton mouse || !mouse.Pressed) return;
        if (mouse.ButtonIndex == MouseButton.Right) right_clicked(owner, button);
        if (!folder && mouse.ButtonIndex == MouseButton.Left && mouse.DoubleClick)
        {
            owner.EmitSignal(path.GetExtension().ToLowerInvariant() == "gdshader" ? "shader_file_opened" : "file_resource_opened", path);
            owner.GetViewport().SetInputAsHandled();
        }
    }
    public bool begin_press(Control owner, Control button)
    {
        var selector = Field(owner, "files_selector");
        bool selected = selector.Call("expandable_button_is_selected", button).AsBool();
        if (!selected) selector.Call("handle_input_for_clicked_file", button);
        return selected;
    }
    public void finish_press(Control owner, Variant value, bool selected)
    {
        if (value.VariantType != Variant.Type.Object) return;
        var button = value.AsGodotObject() as Node;
        if (!GodotObject.IsInstanceValid(button) || button!.IsQueuedForDeletion()) return;
        if (FileAccess.FileExists(button.GetMeta("path").AsString())) return;
        if (Input.IsActionPressed("left_click")) Field(owner, "file_mover").Call("start_moving_selected_files");
        else if (selected) Field(owner, "files_selector").Call("handle_input_for_clicked_file", button);
    }
    public string[] dragged_paths(Control owner, Control button)
    {
        var result = new System.Collections.Generic.List<string>();
        var selector = Field(owner, "files_selector");
        if (!selector.Call("expandable_button_is_selected", button).AsBool()) return new[] { button.GetMeta("path").AsString() };
        foreach (var selected in selector.Call("get_expandable_buttons_top_selected_files").AsGodotArray())
        {
            string path = selected.AsGodotObject().GetMeta("path").AsString();
            if (FileAccess.FileExists(path)) result.Add(path);
        }
        return result.Count == 0 ? new[] { button.GetMeta("path").AsString() } : result.ToArray();
    }
    public Godot.Collections.Array<string> paths_from_drag(Variant data)
    {
        var result = new Godot.Collections.Array<string>();
        if (data.VariantType != Variant.Type.Dictionary) return result;
        var dict = data.AsGodotDictionary();
        if (!dict.TryGetValue("paths", out var paths)) return result;
        if (paths.VariantType == Variant.Type.PackedStringArray) foreach (string path in paths.AsStringArray()) result.Add(path.SimplifyPath());
        else if (paths.VariantType == Variant.Type.Array) foreach (var path in paths.AsGodotArray()) result.Add(path.AsString().SimplifyPath());
        return result;
    }
    public bool can_drop(Control owner, Variant data, string folder)
    {
        var paths = paths_from_drag(data);
        return paths.Count != 0 && paths.All(path => FileAccess.FileExists(path) && path.GetBaseDir().SimplifyPath() != folder.SimplifyPath());
    }
    public void drop(Control owner, Variant data, string folder)
    {
        var paths = paths_from_drag(data);
        if (paths.Count != 0) Field(owner, "file_system_callable_actions").Call("move_files", folder, paths);
    }
    public void right_clicked(Control owner, Control button)
    {
        Field(owner, "files_selector").Call("handle_input_for_right_clicked_file", button);
        Field(owner, "file_system_extra_ui").Call("display_operations", button);
    }
    public void toggled(Control owner, string path, bool on)
    {
        var expanded = List(owner, "_expanded_folders");
        if (on) { if (!expanded.Contains(path)) expanded.Add(path); } else expanded.Remove(path);
    }
    public void style(Control owner, Control button, string text, Texture2D icon, bool expandable)
    {
        button.Set("text", text); button.Set("icon", icon);
        button.Set("label_settings", owner.Get("text_settings")); button.Set("panel_stylebox", owner.Get("panel_style"));
        button.Call("get_expandable_icon_button").As<Control>().Visible = expandable;
        Main(button).ActionMode = BaseButton.ActionModeEnum.Press;
    }
    public Godot.Collections.Array<string> button_paths(Array buttons)
    {
        var result = new Godot.Collections.Array<string>();
        foreach (var button in buttons) result.Add(button.AsGodotObject().GetMeta("path").AsString());
        return result;
    }
}
