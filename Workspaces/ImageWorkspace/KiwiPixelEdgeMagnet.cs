using Godot;

[GlobalClass]
public partial class KiwiPixelEdgeMagnet : RefCounted
{
    public KiwiPixelEdgeField? field { get; set; }
    public int previous { get; set; } = -1;
    private readonly PixelEdgeMagnetOperations _operations = new();
    public Vector2[] follow(Vector2 point, double threshold, Vector2 direction) => _operations.follow(this, point, threshold, direction);
    public Vector2[] connected(Vector2 point, double threshold) => _operations.connected(this, point, threshold);
    public static void paint_band(Image mask, Vector2[] path, double width, Rect2I domain, Color tint, bool connect = true)
        => new PixelEdgeMagnetOperations().paint_band(mask, path, width, domain, tint, connect);
}
