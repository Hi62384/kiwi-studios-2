using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class KiwiPixelObjectSegmenter : RefCounted
{
    public KiwiPixelEdgeField? field { get; set; }
    public int[] labels { get; set; } = System.Array.Empty<int>();
    public Color[] means { get; set; } = System.Array.Empty<Color>();
    public int[] areas { get; set; } = System.Array.Empty<int>();
    public Godot.Collections.Array<Settings> graph { get; set; } = new();
    public Settings background { get; set; } = new();
    public float[] distances { get; set; } = System.Array.Empty<float>();
    public int last_seed { get; set; } = -1;
    public Settings border_regions { get; set; } = new();
    public float[] background_distances { get; set; } = System.Array.Empty<float>();
    public float[] foreground_travel { get; set; } = System.Array.Empty<float>();
    public float[] background_travel { get; set; } = System.Array.Empty<float>();
    public PixelObjectSegmenterKernel? _kernel { get; set; }
    public void build(Image image, Rect2I domain)
    {
        _kernel = new PixelObjectSegmenterKernel(); var data = _kernel.build(image, domain);
        field = data["field"].As<KiwiPixelEdgeField>(); labels = data["labels"].AsInt32Array();
        means = data["means"].AsColorArray(); areas = data["areas"].AsInt32Array();
        graph = new Godot.Collections.Array<Settings>(data["graph"].AsGodotArray());
        background = data["background"].AsGodotDictionary(); border_regions = data["border_regions"].AsGodotDictionary(); last_seed = -1;
    }
    public void _sync_costs()
    {
        var state = _kernel!.cost_state(); distances = state["distances"].AsFloat32Array(); last_seed = state["last_seed"].AsInt32();
        background_distances = state["background_distances"].AsFloat32Array(); foreground_travel = state["foreground_travel"].AsFloat32Array(); background_travel = state["background_travel"].AsFloat32Array();
    }
    public void background_costs(int seed) { _kernel!.background_costs(seed); _sync_costs(); }
    public float[] travel_costs(int[] seeds) => _kernel!.travel_costs(seeds);
    public int[] adjacent(Vector2I point) => _kernel!.adjacent(point);
    public static double difference(Color a, Color b) => PixelObjectSegmenterKernel.Difference(a, b);
    public static int color_key(Color color) => PixelObjectSegmenterKernel.ColorKey(color);
    public bool seed_costs(Vector2 point) { bool result = _kernel!.seed_costs(point); _sync_costs(); return result; }
    public static void heap_push(GArray heap, Vector2 item) => new PixelObjectSegmenterOperations().heap_push(heap, item);
    public static Vector2 heap_pop(GArray heap) => new PixelObjectSegmenterOperations().heap_pop(heap);
    public Image? propose(Vector2 point, double threshold) { var result = _kernel!.propose(point, threshold); _sync_costs(); return result; }
}
