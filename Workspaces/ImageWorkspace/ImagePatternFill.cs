using Godot;

[GlobalClass]
public partial class ImagePatternFill : RefCounted
{
    public static Color sample(Image source, Rect2I area, Vector2 point, Godot.Collections.Dictionary settings) => new ImagePatternFillOperations().sample(source, area, point, settings);
}
