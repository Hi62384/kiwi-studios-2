using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentSessionOperations
{
    private static Resource? Scatter(RefCounted session, string id) => Get(Get(Dict(Doc(session), "component_settings"), id, new Settings()).AsGodotDictionary(), "scatter").As<Resource>();
    public bool begin_scatter(RefCounted session, string id)
    {
        var item = _documents.component(Doc(session), id); var scatter = Scatter(session, id); if (item == null || scatter == null || !_documents.editable_component(Doc(session), item)) return false;
        session.Set("_scatter_stroke", new Settings { ["id"] = id, ["paint"] = scatter.Get("paint_regions").AsGodotArray().Duplicate(), ["erase"] = scatter.Get("erase_regions").AsGodotArray().Duplicate() }); return true;
    }
    public void paint_scatter(RefCounted session, Vector2 point, double radius, bool erase)
    {
        var stroke = Dict(session, "_scatter_stroke"); if (stroke.Count == 0) return; var scatter = Scatter(session, stroke["id"].AsString()); if (scatter == null) return;
        scatter.Get(erase ? "erase_regions" : "paint_regions").AsGodotArray().Add(new Vector3(point.X, point.Y, (float)radius)); Changed(session);
    }
    public void apply_scatter_regions(RefCounted session, string id, GArray paint, GArray erase)
    { var scatter = Scatter(session, id); if (scatter != null) { scatter.Set("paint_regions", paint.Duplicate()); scatter.Set("erase_regions", erase.Duplicate()); } }
    public void finish_scatter(RefCounted session, bool cancelled)
    {
        var stroke = Dict(session, "_scatter_stroke"); if (stroke.Count == 0) return; session.Set("_scatter_stroke", new Settings()); string id = stroke["id"].AsString(); var scatter = Scatter(session, id); if (scatter == null) return;
        var paint = stroke["paint"].AsGodotArray(); var erase = stroke["erase"].AsGodotArray(); if (cancelled) { apply_scatter_regions(session, id, paint, erase); Changed(session); return; }
        var nextPaint = scatter.Get("paint_regions").AsGodotArray(); var nextErase = scatter.Get("erase_regions").AsGodotArray(); if (paint.RecursiveEqual(nextPaint) && erase.RecursiveEqual(nextErase)) return;
        nextPaint = nextPaint.Duplicate(); nextErase = nextErase.Duplicate(); var reference = GodotObject.WeakRef(session) ?? throw new InvalidOperationException("Cannot retain scatter history owner.");
        void Apply(GArray a, GArray b) { var owner = reference.GetRef().As<RefCounted>(); if (owner != null) apply_scatter_regions(owner, id, a, b); }
        session.Call("custom_action", "Paint scatter region", Callable.From(() => Apply(paint, erase)), Callable.From(() => Apply(nextPaint, nextErase)), nextPaint.Count + nextErase.Count);
    }
}
