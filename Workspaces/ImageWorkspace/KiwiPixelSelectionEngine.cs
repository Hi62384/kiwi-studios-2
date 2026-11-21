using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiPixelSelectionEngine : Node
{
    [Signal] public delegate void analyzedEventHandler();
    [Signal] public delegate void proposedEventHandler(Image? mask, string kind, long request);
    public KiwiPixelEdgeField? edges { get; set; }
    public KiwiPixelObjectSegmenter? objects { get; set; }
    public Image? source { get; set; }
    public Rect2I domain { get; set; }
    public GodotThread? _thread { get; set; }
    public Settings _job { get; set; } = new();
    public Settings _pending { get; set; } = new();
    public long _generation { get; set; }
    public long _request { get; set; }
    private readonly PixelSelectionEngineOperations _operations = new();
    public void prepare(Image image, Rect2I area) => _operations.prepare(this, image, area);
    public void invalidate() => _operations.invalidate(this);
    public void cancel_request() => _operations.cancel_request(this);
    public long request(string kind, Vector2 seed, double threshold) => request(kind, seed, threshold, 1, new Settings());
    public long request(string kind, Vector2 seed, double threshold, double width) => request(kind, seed, threshold, width, new Settings());
    public long request(string kind, Vector2 seed, double threshold, double width, Settings coverage) => _operations.request(this, kind, seed, threshold, width, coverage);
    public override void _Process(double delta) => _operations.process(this);
    public Settings _work(Settings job) => _operations.work(job);
    public Image? _finish_mask(Image? mask, Settings job) => _operations.finish_mask(mask, job);
    public override void _ExitTree() => _operations.exit_tree(this);
}
