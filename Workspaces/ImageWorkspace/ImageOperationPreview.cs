using Godot;

[GlobalClass]
public partial class ImageOperationPreview : Control
{
    private Texture2D? _texture;
    public Texture2D? texture { get => _texture; set { _texture = value; QueueRedraw(); } }
    public double zoom { get; set; } = 1;
    public Vector2 pan { get; set; } = Vector2.Zero;
    public bool dragging { get; set; }
    private readonly ImageOperationPreviewOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public override void _Draw() => _operations.draw(this);
    public override void _GuiInput(InputEvent @event) => _operations.gui_input(this, @event);
}
