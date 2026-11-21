using Godot;

[GlobalClass]
public partial class ImageSoftenBrush : RefCounted
{
    public static Image prepare(Image source, double radius) => new ImageSoftenBrushOperations().prepare(source, radius);
    public static Image composite(Image baseline, Image filtered, Image ink, Rect2I area, double strength, double opacity, Variant coverage, bool opaque)
        => new ImageSoftenBrushOperations().composite(baseline, filtered, ink, area, strength, opacity, coverage, EngineVariantDispatch.CallableValid(coverage), opaque);
    public static double _coverage_value(Variant callback, Vector2 point)
    {
        using var arguments = new Godot.Collections.Array { point };
        using var result = EngineVariantDispatch.InvokeCallable(callback, arguments);
        return result.AsDouble();
    }
}
