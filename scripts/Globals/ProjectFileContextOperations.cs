using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class ProjectFileContextOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private readonly ProjectFileSelectionOperations _selection = new();
    private readonly LocalProjectFilesystemOperations _project = new();
    private readonly SuperClipboardOperations _clipboard = new();
    private static T Field<T>(Node owner, string key) where T : GodotObject => (T)owner.Get(key).AsGodotObject();
    private static Control Browser(Node owner) => Field<Control>(owner, "file_system");
    private static Node Actions(Node owner) => Field<Node>(owner, "file_system_callable_actions");
    public void ready(Node owner)
    {
        Field<Button>(owner, "delete_file_panel_close_button").Connect("pressed", new Callable(owner, "_close_delete_panel")); Field<Button>(owner, "delete_file_panel_delete_button").Connect("pressed", new Callable(owner, "delete_files")); Field<Button>(owner, "delete_file_panel_to_recycle_bin_button").Connect("pressed", new Callable(owner, "recycle_files"));
    }
    public void display_operations(Node owner, Control button)
    {
        owner.Set("_clicked_expandable_button", button); var dialogue = GD.Load<PackedScene>("uid://cm431qw86wyvs").Instantiate<Control>(); owner.Set("_current_dialouge", dialogue); dialogue.Position = Browser(owner).GetGlobalMousePosition(); owner.AddChild(dialogue);
        foreach (var pair in new[] { ("copy_path_button", "copy_file_path"), ("copy_absolute_path_button", "copy_absolute_file_path"), ("show_in_file_manager_button", "_show_in_file_manager"), ("open_in_external_program_button", "_open_in_external_program"), ("rename_button", "rename_file"), ("create_new_folder_button", "create_folder"), ("delete_button", "show_delete_options"), ("duplicate_button", "duplicate_files") }) dialogue.Get(pair.Item1).As<Button>().Connect("pressed", new Callable(owner, pair.Item2));
        var clipboard = new Button { Text = "Copy to Super Clipboard" }; dialogue.Get("duplicate_button").As<Button>().GetParent().AddChild(clipboard);
        clipboard.Pressed += () =>
        {
            if (GodotObject.IsInstanceValid(owner))
            {
                var service = GD.Load<GDScript>("res://scripts/clipboard/super_clipboard_service.gd").Get("instance");
                if (service.VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(service.AsGodotObject())) foreach (string path in selected_paths(owner)) if (FileAccess.FileExists(path)) _clipboard.quick_save((Node)service.AsGodotObject(), path, path.GetFile().GetBaseName(), "default");
            }
            if (GodotObject.IsInstanceValid(dialogue)) dialogue.QueueFree();
        };
    }
    public Godot.Collections.Array<string> selected_paths(Node owner)
    {
        var result = new Godot.Collections.Array<string>(); foreach (var value in _selection.top_selected_files(Browser(owner).Get("files_selector").As<Node>())) result.Add(value.AsGodotObject().GetMeta("path").AsString()); return result;
    }
    public void set_panel_visible(Node owner, Control panel, bool visible) { panel.Visible = visible; Field<Control>(owner, "screen_cover").Visible = visible; }
    public string clicked_path(Node owner)
    {
        var value = owner.Get("_clicked_expandable_button"); return value.VariantType == Variant.Type.Object && value.AsGodotObject() is Node button && GodotObject.IsInstanceValid(button) && !button.IsQueuedForDeletion() ? button.GetMeta("path").AsString() : "";
    }
    public void copy_file_path(Node owner) => DisplayServer.ClipboardSet(_project.global_to_local_path(clicked_path(owner)));
    public void copy_absolute_file_path(Node owner) => DisplayServer.ClipboardSet(clicked_path(owner));
    public void show_in_file_manager(Node owner) { string path = clicked_path(owner); if (path != "") _files.open_file(_files.get_lowest_directory(path)); }
    public void open_in_external_program(Node owner) { string path = clicked_path(owner); if (path != "") _files.open_file(path); }
    public string begin_rename(Node owner)
    {
        string path = clicked_path(owner); if (path == "") return ""; Field<Control>(owner, "screen_cover").Visible = true; Field<LineEdit>(owner, "rename_file_panel_line_edit").Text = path.GetBaseName().GetFile(); return path;
    }
    public void finish_rename(Node owner, string path, Settings result)
    {
        Field<Control>(owner, "screen_cover").Visible = false; if (result.Count > 0 && path != "") Actions(owner).Call("rename_file", path, result["NewFileName"]);
    }
    public string begin_create_folder(Node owner)
    {
        string path = clicked_path(owner); if (path == "") return ""; Field<Control>(owner, "screen_cover").Visible = true; return _files.get_lowest_directory(path);
    }
    public void finish_create_folder(Node owner, string directory, Settings result)
    {
        Field<Control>(owner, "screen_cover").Visible = false; if (result.Count > 0 && directory != "") Actions(owner).Call("create_folder", directory.PathJoin(result["FolderName"].AsString()));
    }
    public void duplicate_files(Node owner) => Actions(owner).Call("duplicate_files", selected_paths(owner));
    public void show_delete_options(Node owner) => set_panel_visible(owner, Field<Control>(owner, "delete_file_panel"), true);
    public void close_delete_panel(Node owner) => set_panel_visible(owner, Field<Control>(owner, "delete_file_panel"), false);
    public void delete_files(Node owner) { close_delete_panel(owner); Actions(owner).Call("delete_files", selected_paths(owner)); }
    public void recycle_files(Node owner) { close_delete_panel(owner); Actions(owner).Call("send_files_to_recycle_bin", selected_paths(owner)); }
    public void for_top_files(Node owner, Variant callback)
    {
        foreach (var value in _selection.top_selected_files(Browser(owner).Get("files_selector").As<Node>())) owner.Call("_invoke_file_callback", callback, value, value.AsGodotObject().GetMeta("path"));
    }
}
