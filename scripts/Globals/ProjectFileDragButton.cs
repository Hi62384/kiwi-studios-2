using Godot;
using System;
using System.Linq;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ProjectFileDragButton : Button
{
    // Incoming GDScript callables stay in Variant form throughout dispatch.
    public Variant drag_paths_provider { get; set; }
    public Variant accepts_drop { get; set; }
    public Variant receives_drop { get; set; }
    private readonly ProjectFileInputOperations _operations = new();
    public override Variant _GetDragData(Vector2 atPosition) => _operations.drag_data(this);
    public override bool _CanDropData(Vector2 atPosition, Variant data)
    {
        using var arguments = new GArray { data };
        return EngineVariantDispatch.InvokeCallable(accepts_drop, arguments).AsBool();
    }
    public override void _DropData(Vector2 atPosition, Variant data)
    {
        if (!EngineVariantDispatch.CallableValid(receives_drop) || !_CanDropData(Vector2.Zero, data)) return;
        using var arguments = new GArray { data };
        EngineVariantDispatch.InvokeCallable(receives_drop, arguments);
    }
    public string[] _native_drag_paths()
    {
        using var arguments = new GArray();
        var result = EngineVariantDispatch.InvokeCallable(drag_paths_provider, arguments);
        if (result.VariantType == Variant.Type.PackedStringArray) return result.AsStringArray();
        if (result.VariantType == Variant.Type.Array) return result.AsGodotArray().Select(value => value.AsString()).ToArray();
        if (result.VariantType != Variant.Type.Nil) GD.PushError("The file-drag path provider must return file paths.");
        return Array.Empty<string>();
    }
}
