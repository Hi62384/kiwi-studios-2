using Godot;

[GlobalClass]
public partial class PixelSelectionAlpha : RefCounted
{
    public static Image stamp(double diameter, double falloff) => new PixelSelectionAlphaOperations().stamp(diameter, falloff);
    public static Image blend(Image baseline, Image coverage, double amount, bool subtract, Vector2I origin)
        => new PixelSelectionAlphaOperations().blend(baseline, coverage, amount, subtract, origin);
    public static void blend_region(Image result, Image baseline, Image coverage, Rect2I area, double amount, bool subtract)
        => new PixelSelectionAlphaOperations().blend_region(result, baseline, coverage, area, amount, subtract);
    public static Image feather(Image mask, double falloff) => new PixelSelectionAlphaOperations().feather(mask, falloff);
}
