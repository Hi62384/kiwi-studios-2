using Godot;
using System.Collections.Generic;

public partial class CompositeWorkspaceHistory : RefCounted
{
    private readonly List<Resource> _undo = new();
    private readonly List<Resource> _redo = new();
    private readonly CompositingDocument _rules = new();
    public void clear() { _undo.Clear(); _redo.Clear(); }
    public bool commit(Resource current, Resource snapshot)
    {
        if (_rules.signature_resource(current) == _rules.signature_resource(snapshot)) return false;
        _undo.Add(snapshot); if (_undo.Count > 100) _undo.RemoveAt(0);
        _redo.Clear(); return true;
    }
    public Resource? undo(Resource current)
    {
        if (_undo.Count == 0) return null;
        _redo.Add((Resource)current.Duplicate(true)); var result = _undo[^1]; _undo.RemoveAt(_undo.Count - 1); return result;
    }
    public Resource? redo(Resource current)
    {
        if (_redo.Count == 0) return null;
        _undo.Add((Resource)current.Duplicate(true)); var result = _redo[^1]; _redo.RemoveAt(_redo.Count - 1); return result;
    }
}
