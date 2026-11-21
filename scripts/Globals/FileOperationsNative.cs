using Godot;
using System;
using System.Linq;

/// <summary>Filesystem operations shared by project browsers and resource inspectors.</summary>
public partial class FileOperationsNative : RefCounted
{
    private static GDScript ProjectFiles => GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd");
    public FileDialogSelection begin_dialog(FileDialog dialog) { var state = new FileDialogSelection(); state.initialize(dialog); return state; }
    public bool is_path_inside(string parent, string child)
    {
        parent = parent.Replace('\\', '/').SimplifyPath();
        child = child.Replace('\\', '/').SimplifyPath();
        var comparison = OS.GetName() == "Windows" ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        return string.Equals(parent, child, comparison) || child.StartsWith(parent.TrimEnd('/') + "/", comparison);
    }
    public bool file_is_sensitive(string path)
    {
        string normalized = ProjectSettings.GlobalizePath(path).Replace('\\', '/').SimplifyPath().TrimEnd('/');
        var comparison = OS.GetName() == "Windows" ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        return ProjectFiles.Call("get_sensetive_file_paths").AsGodotArray().Any(value => string.Equals(ProjectSettings.GlobalizePath(value.AsString()).Replace('\\', '/').SimplifyPath().TrimEnd('/'), normalized, comparison));
    }
    public bool path_exists(string path) => FileAccess.FileExists(path) || DirAccess.DirExistsAbsolute(path);
    public string get_lowest_directory(string path) => DirAccess.DirExistsAbsolute(path) || path.GetExtension() == "" ? path : path.GetBaseDir();
    public void update_project(string path)
    {
        if (ProjectFiles.Call("file_exists_in_project_directory", path).AsBool()) ProjectFiles.Call("update_root_folder");
    }
    public string get_tres_type(string path)
    {
        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        if (file == null) return "";
        string header = file.GetLine();
        foreach (string key in new[] { "script_class", "type" })
        {
            var match = System.Text.RegularExpressions.Regex.Match(header, key + "=\"([^\"]+)\"");
            if (match.Success) return match.Groups[1].Value;
        }
        return "";
    }
    public bool dir_path_string_is_valid(string path)
    {
        if (path == "") return false;
        string basename = path.GetBaseName();
        return !new[] { "<", ">", "\"", "'", "\\", "//", "|", "?", "*", "." }.Any(basename.Contains);
    }
    public string get_changed_name_path(string path, string name)
    {
        string extension = path.GetExtension();
        return path.GetBaseDir() + "/" + name + (extension == "" ? "" : "." + extension);
    }
    public string get_unique_name(string path)
    {
        while (path_exists(path)) path = get_changed_name_path(path, path.GetBaseName().GetFile() + "-copy");
        return path;
    }
    public void delete_directory(string path)
    {
        if (file_is_sensitive(path)) return;
        foreach (string file in DirAccess.GetFilesAt(path)) delete_file(path.PathJoin(file));
        foreach (string folder in DirAccess.GetDirectoriesAt(path)) delete_directory(path.PathJoin(folder));
        DirAccess.RemoveAbsolute(path);
        update_project(path);
    }
    public void create_folder_at(string path)
    {
        if (!dir_path_string_is_valid(path)) return;
        path = get_unique_name(path);
        DirAccess.MakeDirRecursiveAbsolute(path);
        update_project(path);
    }
    public void delete_file(string path)
    {
        if (file_is_sensitive(path)) return;
        DirAccess.RemoveAbsolute(path);
        update_project(path);
    }
    public void move_to_trash(string path)
    {
        if (file_is_sensitive(path)) return;
        OS.MoveToTrash(path);
        update_project(path);
    }
    public void move_to_project_trash(string path)
    {
        if (file_is_sensitive(path)) return;
        string trash = ProjectFiles.Call("get_project_trash_directory").AsString();
        if (trash == "") return;
        move_absolute(path, trash);
        update_project(path);
    }
    public void flush_project_trash()
    {
        string path = ProjectFiles.Call("get_project_trash_directory").AsString();
        if (path == "") return;
        foreach (string file in DirAccess.GetFilesAt(path)) move_to_trash(path.PathJoin(file));
        foreach (string folder in DirAccess.GetDirectoriesAt(path)) move_to_trash(path.PathJoin(folder));
    }
    public void open_file(string path) => OS.ShellOpen(path);
    public void move_absolute(string from, string directory)
    {
        if (file_is_sensitive(from)) return;
        string target = directory.PathJoin(from.GetFile());
        if (path_exists(target)) return;
        DirAccess.RenameAbsolute(from, target);
        update_project(from);
    }
    public void move_files(string target, Godot.Collections.Array<string> sources)
    {
        target = get_lowest_directory(target);
        foreach (string source in sources)
            if (!is_path_inside(source, target)) move_absolute(source, target);
    }
    public void rename_absolute(string path, string name)
    {
        if (file_is_sensitive(path) || !dir_path_string_is_valid(name)) return;
        DirAccess.RenameAbsolute(path, get_changed_name_path(path, name));
        update_project(path);
    }
    public void duplicate_path_absolute(string from, string to)
    {
        if (DirAccess.DirExistsAbsolute(from)) duplicate_directory(from, to);
        else duplicate_file(from, to);
    }
    public void duplicate_directory(string from, string to)
    {
        if (file_is_sensitive(from) || !dir_path_string_is_valid(to)) return;
        to = get_unique_name(to);
        // Reject copying a directory into itself: otherwise recursion never terminates.
        if (is_path_inside(from, to)) return;
        using var directory = DirAccess.Open(from);
        if (directory == null) { GD.PushWarning("Error opening source directory: " + from); return; }
        DirAccess.MakeDirRecursiveAbsolute(to);
        directory.ListDirBegin();
        for (string name = directory.GetNext(); name != ""; name = directory.GetNext())
        {
            if (name is "." or "..") continue;
            string source = from.PathJoin(name), target = to.PathJoin(name);
            if (directory.CurrentIsDir()) duplicate_directory(source, target);
            else if (DirAccess.CopyAbsolute(source, target) != Error.Ok) GD.PushWarning("Failed to copy file: " + source);
        }
        directory.ListDirEnd();
        update_project(from);
    }
    public void duplicate_file(string from, string to)
    {
        if (file_is_sensitive(from) || !dir_path_string_is_valid(to)) return;
        DirAccess.CopyAbsolute(from, get_unique_name(to));
        update_project(from);
    }
    public void save_resource(Resource resource) => ResourceSaver.Save(resource, resource.ResourcePath);
    public Texture2D? load_image(string path)
    {
        using var image = Image.LoadFromFile(path);
        return image == null ? null : ImageTexture.CreateFromImage(image);
    }
}
