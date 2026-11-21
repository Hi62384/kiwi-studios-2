using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ImageLiveEraser : RefCounted
{
    public Godot.Collections.Array<Settings> regions { get; set; } = new();
    public Vector2I source_size { get; set; } = Vector2I.Zero;
    private readonly ImageLiveEraserOperations _operations = new();
    public void begin(KiwiImageLayer layer, Vector2I size) => _operations.begin(this, layer, size);
    public void apply(Rect2I area, Image coverage) => _operations.apply(this, area, coverage);
}
