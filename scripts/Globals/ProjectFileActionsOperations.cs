using Godot;
using System;
using System.Collections.Generic;

public partial class ProjectFileActionsOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private static UndoRedo History(Node owner) => owner.Get("_undo_redo").As<UndoRedo>();
    private static void Commit(Node owner, string title, ProjectFileHistoryAction action)
    {
        if (action.Count == 0) { action.Dispose(); return; }
        var history = History(owner); history.CreateAction(title); history.AddDoMethod(new Callable(action, "apply")); history.AddUndoMethod(new Callable(action, "revert")); history.AddDoReference(action); history.AddUndoReference(action); history.CommitAction();
    }
    public void exit_tree(Node owner) { var history = History(owner); if (GodotObject.IsInstanceValid(history)) { history.ClearHistory(); history.Free(); owner.Set("_undo_redo", default); } }
    public void undo(Node owner) => History(owner).Undo();
    public void redo(Node owner) => History(owner).Redo();
    public void move_files(Node owner, string destination, Godot.Collections.Array<string> paths)
    {
        destination = _files.get_lowest_directory(destination); var action = new ProjectFileHistoryAction(); var planned = new HashSet<string>(OS.GetName() == "Windows" ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        foreach (string path in paths)
        {
            string target = destination.PathJoin(path.GetFile());
            if (_files.file_is_sensitive(path) || !_files.path_exists(path) || _files.is_path_inside(path, destination) || _files.path_exists(target) || !planned.Add(target)) continue;
            action.Add("move", path, target);
        }
        Commit(owner, "Move Files", action);
    }
    public void send_files_to_recycle_bin(Node owner, Godot.Collections.Array<string> paths)
    {
        string trash = new LocalProjectFilesystemOperations().get_project_trash_directory(); if (trash == "") return; move_files(owner, trash, paths);
    }
    public void delete_files(Godot.Collections.Array<string> paths)
    {
        foreach (string path in paths) { if (DirAccess.DirExistsAbsolute(path)) _files.delete_directory(path); else _files.delete_file(path); }
    }
    public void duplicate_files(Node owner, Godot.Collections.Array<string> paths)
    {
        var action = new ProjectFileHistoryAction(); var planned = new HashSet<string>(OS.GetName() == "Windows" ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal); var sources = new HashSet<string>(OS.GetName() == "Windows" ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        foreach (string path in paths)
        {
            if (!_files.path_exists(path) || _files.file_is_sensitive(path) || !sources.Add(path)) continue;
            string target = _files.get_unique_name(path);
            while (planned.Contains(target)) target = _files.get_changed_name_path(target, target.GetBaseName().GetFile() + "-copy");
            if (DirAccess.DirExistsAbsolute(path) && _files.is_path_inside(path, target)) continue; planned.Add(target); action.Add("copy", path, target);
        }
        Commit(owner, "Duplicate Files", action);
    }
    public void create_folder(Node owner, string path)
    {
        if (!_files.dir_path_string_is_valid(path)) return; var action = new ProjectFileHistoryAction(); action.Add("folder", "", _files.get_unique_name(path)); Commit(owner, "Create Folder", action);
    }
    public void rename_file(Node owner, string path, string name)
    {
        if (!_files.path_exists(path) || _files.file_is_sensitive(path) || !_files.dir_path_string_is_valid(name)) return;
        string target = _files.get_changed_name_path(path, name); if (target == path || (_files.path_exists(target) && !(OS.GetName() == "Windows" && string.Equals(path, target, StringComparison.OrdinalIgnoreCase)))) return;
        var action = new ProjectFileHistoryAction(); action.Add("move", path, target); Commit(owner, "Change Filename", action);
    }
}
