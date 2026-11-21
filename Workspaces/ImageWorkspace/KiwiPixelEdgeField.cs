using Godot;

[GlobalClass]
public partial class KiwiPixelEdgeField : RefCounted
{
    public Image? source { get; set; }
    public Rect2I domain { get; set; }
    public Image? bitmap { get; set; }
    public Vector2I size { get; set; }
    public Vector2 step { get; set; }
    public float[] strength { get; set; } = System.Array.Empty<float>();
    public Vector2[] normal { get; set; } = System.Array.Empty<Vector2>();
    public byte[] ridges { get; set; } = System.Array.Empty<byte>();
    public Color[] colors { get; set; } = System.Array.Empty<Color>();
    public PixelEdgeFieldKernel? _kernel { get; set; }
    public void build(Image image, Rect2I area) => build(image, area, 768);
    public void build(Image image, Rect2I area, int maximum)
    {
        source = image;
        _kernel = new PixelEdgeFieldKernel();
        var data = _kernel.build(image, area, maximum);
        domain = data["domain"].AsRect2I(); bitmap = data["bitmap"].As<Image>();
        size = data["size"].AsVector2I(); step = data["step"].AsVector2();
        strength = data["strength"].AsFloat32Array(); normal = data["normal"].AsVector2Array();
        ridges = data["ridges"].AsByteArray(); colors = data["colors"].AsColorArray();
    }
    public float sample_strength(Vector2 point) => _kernel!.sample_strength(point);
    public bool inside(Vector2I point) => _kernel!.inside(point);
    public Vector2 position(int index) => _kernel!.position(index);
    public Vector2I cell(Vector2 point) => _kernel!.cell(point);
    public double cutoff(double value) => .012 + .75 * System.Math.Pow(System.Math.Clamp(value, 0, 1), 2);
    public int nearest(Vector2 point, double threshold) => nearest(point, threshold, -1, Vector2.Zero);
    public int nearest(Vector2 point, double threshold, int previous) => nearest(point, threshold, previous, Vector2.Zero);
    public int nearest(Vector2 point, double threshold, int previous, Vector2 direction) => _kernel!.nearest(point, threshold, previous, direction);
    public int[] neighbors(int index, double threshold) => _kernel!.neighbors(index, threshold);
    public Vector2 refine(int index) => _kernel!.refine(index);
}
