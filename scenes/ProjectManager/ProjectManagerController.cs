using Godot;
using System.IO;

public partial class ProjectManagerController : Node
{
    [Signal] public delegate void saved_projects_updatedEventHandler();
    private Resource _listing = null!;
    private string _listingPath = "";
    [Export] public string ListingPathOverride { get; set; } = "";

    public override void _Ready()
    {
        string root = OS.HasFeature("editor") ? ProjectSettings.GlobalizePath("res://") : OS.GetExecutablePath().GetBaseDir();
        string legacy = root.PathJoin("_SavedProjects.tres");
        _listingPath = OS.HasFeature("editor") ? legacy : "user://saved_projects.tres";
        if (ListingPathOverride.Length > 0) _listingPath = ListingPathOverride;
        if (Godot.FileAccess.FileExists(_listingPath)) _listing = GD.Load<Resource>(_listingPath);
        else if (ListingPathOverride.Length == 0 && !OS.HasFeature("editor") && Godot.FileAccess.FileExists(legacy)) _listing = GD.Load<Resource>(legacy).Duplicate(true);
        _listing ??= new ProjectManagerSavedProjects();
        _listing.TakeOverPath(_listingPath);
    }

    public Resource get_saved_projects() => _listing;
    private Godot.Collections.Array<string> Paths => new(_listing.Get("project_paths").AsGodotArray());

    private void StorePaths(Godot.Collections.Array<string> paths)
    {
        _listing.Set("project_paths", paths);
        Error error = ResourceSaver.Save(_listing, _listingPath);
        if (error != Error.Ok) GD.PushError($"Project list could not be saved: {error}");
        EmitSignal(SignalName.saved_projects_updated);
    }

    public void add_project_to_listing(string path)
    {
        var paths = Paths;
        if (!paths.Contains(path)) paths.Add(path);
        StorePaths(paths);
    }

    public void remove_project_from_listing(string path)
    {
        var paths = Paths; paths.Remove(path); StorePaths(paths);
    }

    public string get_project_file_path_in_project_dir(string path)
    {
        string file = path.PathJoin(".proj/Project.tres");
        return Godot.FileAccess.FileExists(file) ? file : "";
    }

    public void create_project(string path, string project_name)
    {
        if (Paths.Contains(path)) return;
        string folder = path.PathJoin(".proj");
        Error error = DirAccess.MakeDirRecursiveAbsolute(folder.PathJoin(".trash"));
        if (error != Error.Ok) { GD.PushError($"Cannot create project directory: {error}"); return; }
        var project = new Project(project_name);
        error = ResourceSaver.Save(project, folder.PathJoin("Project.tres"));
        if (error == Error.Ok) add_project_to_listing(path);
        else GD.PushError($"Cannot save project: {error}");
    }

    public void rename_project(string project_path, string new_name)
    {
        string file = get_project_file_path_in_project_dir(project_path);
        if (file.Length == 0) return;
        var project = GD.Load<Resource>(file); project.Set("project_name", new_name);
        if (ResourceSaver.Save(project, file) == Error.Ok) EmitSignal(SignalName.saved_projects_updated);
    }

    public void duplicate_project(string source, string destination, string project_name)
    {
        string from = Path.GetFullPath(ProjectSettings.GlobalizePath(source));
        string to = Path.GetFullPath(ProjectSettings.GlobalizePath(destination));
        if (!Directory.Exists(from) || to.Equals(from, System.StringComparison.OrdinalIgnoreCase)
            || to.StartsWith(from.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, System.StringComparison.OrdinalIgnoreCase)
            || Directory.Exists(to)) return;
        try
        {
            CopyDirectory(from, to); rename_project(destination, project_name); add_project_to_listing(destination);
        }
        catch (System.Exception exception) { GD.PushError($"Project duplication failed: {exception.Message}"); }
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), false);
        foreach (string directory in Directory.GetDirectories(source))
        {
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0) continue;
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
        }
    }

    public void unalive_project_directory(string path, bool to_recycle_bin)
    {
        string absolute = Path.GetFullPath(ProjectSettings.GlobalizePath(path));
        if (!Directory.Exists(absolute) || get_project_file_path_in_project_dir(path).Length == 0) return;
        try
        {
            if (to_recycle_bin) { if (OS.MoveToTrash(absolute) != Error.Ok) return; }
            else Directory.Delete(absolute, true);
            remove_project_from_listing(path);
        }
        catch (System.Exception exception) { GD.PushError($"Project removal failed: {exception.Message}"); }
    }
}
