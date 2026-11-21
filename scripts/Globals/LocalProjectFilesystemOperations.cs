using Godot;
using System;

public partial class LocalProjectFilesystemOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private static GDScript Bridge => GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd");
    private static Godot.Collections.Array Paths => Bridge.Get("_all_files_paths").AsGodotArray();
    public Resource? get_current_project()
    {
        var value = Variant.From(StaticData.get_loaded_project()); return value.VariantType == Variant.Type.Object ? value.AsGodotObject() as Resource : null;
    }
    public string get_project_root_directory() => get_current_project()?.ResourcePath.GetBaseDir().GetBaseDir() ?? "";
    public string get_project_trash_directory() { string root = get_project_root_directory(); return root == "" ? "" : root.PathJoin(".proj/.trash"); }
    public string local_to_global_path(Variant path) => get_project_root_directory() + "/" + path.ToString();
    public bool file_exists_in_project_directory(string path) { string root = get_project_root_directory(); return root != "" && _files.is_path_inside(root, path); }
    public string global_to_local_path(string path)
    {
        string root = get_project_root_directory(); if (root == "" || !_files.is_path_inside(root, path)) return ""; return path.Length >= root.Length ? path[root.Length..] : "";
    }
    public Godot.Collections.Array<string> get_sensetive_file_paths()
    {
        string root = get_project_root_directory(); return root == "" ? new() : new() { root, root.PathJoin(".proj"), root.PathJoin(".proj/.trash"), root.PathJoin(".proj/Project.tres") };
    }
    public void begin_ready(Node owner) { Bridge.Set("node", owner); if (get_current_project() != null) _files.flush_project_trash(); }
    public void finish_ready(Node owner)
    {
        update_root_folder(); var timer = new Timer { WaitTime = 3 }; owner.AddChild(timer); timer.Connect("timeout", new Callable(owner, "_scan_changes")); timer.Start();
    }
    public void exit_tree(Node owner) { if (Bridge.Get("node").AsGodotObject() == owner) Bridge.Set("node", default); }
    public void scan_changes()
    {
        if (get_current_project() == null) return; var remaining = Paths.Duplicate(); if (remaining.Count > 0) remaining.RemoveAt(0);
        // Rebuild once after a change instead of recursively rebuilding and then
        // rebuilding again as the changed branch unwinds.
        int result = Scan(get_project_root_directory(), remaining, 0); if (result != remaining.Count) update_root_folder();
    }
    private int Scan(string folder, Godot.Collections.Array paths, int index)
    {
        foreach (string child in DirAccess.GetDirectoriesAt(folder))
        {
            string path = folder.PathJoin(child); if (index >= paths.Count || path != paths[index].AsString()) return -1;
            index = Scan(path, paths, index + 1); if (index == -1) return -1;
        }
        foreach (string child in DirAccess.GetFilesAt(folder)) { string path = folder.PathJoin(child); if (index >= paths.Count || path != paths[index].AsString()) return -1; index++; }
        return index;
    }
    public int scan_folder_for_change(string folder, Godot.Collections.Array<string> remaining, int index)
    {
        var paths = new Godot.Collections.Array(); foreach (string path in remaining) paths.Add(path); int result = Scan(folder, paths, index); if (result == -1) update_root_folder(); return result;
    }
    public void update_root_folder()
    {
        string root = get_project_root_directory(); if (root == "") return;
        Bridge.Set("root_folder", create_file_tree(root)); var node = Bridge.Get("node"); if (node.VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(node.AsGodotObject())) node.AsGodotObject().EmitSignal("file_tree_recreated");
    }
    private static RefCounted NewFile(string path, bool folder) => Bridge.Call("_new_native_file", path, folder).As<RefCounted>();
    public RefCounted create_file_tree(string folder)
    {
        Bridge.Set("_all_files_paths", new Godot.Collections.Array<string> { folder }); var root = NewFile(folder, true); recursive_add_files_in_folder(root); return root;
    }
    public void recursive_add_files_in_folder(RefCounted folder)
    {
        string path = folder.Get("path").AsString(); var children = folder.Get("contains").AsGodotArray();
        foreach (string name in DirAccess.GetDirectoriesAt(path))
        {
            string childPath = path.PathJoin(name); var child = NewFile(childPath, true); children.Add(child); Paths.Add(childPath); recursive_add_files_in_folder(child);
        }
        foreach (string name in DirAccess.GetFilesAt(path)) { string childPath = path.PathJoin(name); Paths.Add(childPath); children.Add(NewFile(childPath, false)); }
    }
    public Godot.Collections.Array<string> get_ordered_array_of_project_file_paths()
    {
        // Preserve the original shared typed array returned by the facade.
        return Bridge.Get("_all_files_paths").AsGodotArray<string>();
    }
}
