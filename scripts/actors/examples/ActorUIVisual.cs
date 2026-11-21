using Godot;

[GlobalClass]
public partial class ActorUIVisual : Node2D
{
    internal static Texture2D? SharedSolidTexture { get; set; }
    public Vector2 dimensions { get; set; } = new(400, 240);
    public Texture2D? texture { get; set; }
    public long shape { get; set; } = -1;
    public Color fill { get; set; } = Colors.White;
    public Color outline { get; set; } = Colors.White;
    public double width { get; set; }
    public Texture2D? solid_texture { get; set; }
    private readonly UiActorOperations _operations = new();
    public override void _Ready() => _operations.visual_ready(this);
    public override void _Draw() => _operations.visual_draw(this);
    internal static void ClearCache() => SharedSolidTexture = null;
}
