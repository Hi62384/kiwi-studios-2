using Godot;
using System;
using System.Collections.Generic;

/// <summary>Owns exact paths and successful outcomes for one filesystem history entry.</summary>
public partial class ProjectFileHistoryAction : RefCounted
{
    public record Operation(string Kind, string From, string To);
    private readonly List<Operation> _operations = new();
    private readonly List<bool> _applied = new();
    private readonly FileOperationsNative _files = new();
    public void Add(string kind, string from, string to) { _operations.Add(new Operation(kind, from, to)); _applied.Add(false); }
    public int Count => _operations.Count;
    public void apply()
    {
        for (int i = 0; i < _operations.Count; i++)
        {
            var operation = _operations[i]; _applied[i] = false;
            bool caseRename = OS.GetName() == "Windows" && operation.Kind == "move" && !string.Equals(operation.From, operation.To, StringComparison.Ordinal) && string.Equals(operation.From, operation.To, StringComparison.OrdinalIgnoreCase);
            if (_files.path_exists(operation.To) && !caseRename) { GD.PushWarning("File action skipped an existing destination: " + operation.To); continue; }
            if (operation.Kind != "folder" && (!_files.path_exists(operation.From) || _files.file_is_sensitive(operation.From))) continue;
            if (operation.Kind == "move")
            {
                if (DirAccess.RenameAbsolute(operation.From, operation.To) != Error.Ok) continue;
                _applied[i] = true; _files.update_project(operation.From); _files.update_project(operation.To);
            }
            else if (operation.Kind == "copy")
            {
                if (DirAccess.DirExistsAbsolute(operation.From)) { _files.duplicate_directory(operation.From, operation.To); _applied[i] = DirAccess.DirExistsAbsolute(operation.To); }
                else { _applied[i] = DirAccess.CopyAbsolute(operation.From, operation.To) == Error.Ok; if (_applied[i]) _files.update_project(operation.To); }
            }
            else if (operation.Kind == "folder")
            {
                _applied[i] = DirAccess.MakeDirRecursiveAbsolute(operation.To) == Error.Ok; if (_applied[i]) _files.update_project(operation.To);
            }
        }
    }
    public void revert()
    {
        for (int i = _operations.Count - 1; i >= 0; i--)
        {
            if (!_applied[i]) continue; var operation = _operations[i];
            if (!_files.path_exists(operation.To) || _files.file_is_sensitive(operation.To)) continue;
            if (operation.Kind == "move")
            {
                bool caseRename = OS.GetName() == "Windows" && !string.Equals(operation.From, operation.To, StringComparison.Ordinal) && string.Equals(operation.From, operation.To, StringComparison.OrdinalIgnoreCase);
                if (_files.path_exists(operation.From) && !caseRename) { GD.PushWarning("Undo skipped an existing destination: " + operation.From); continue; }
                if (DirAccess.RenameAbsolute(operation.To, operation.From) == Error.Ok) { _applied[i] = false; _files.update_project(operation.To); _files.update_project(operation.From); }
            }
            else
            {
                if (DirAccess.DirExistsAbsolute(operation.To)) _files.delete_directory(operation.To); else _files.delete_file(operation.To);
                if (!_files.path_exists(operation.To)) _applied[i] = false;
            }
        }
    }
}
