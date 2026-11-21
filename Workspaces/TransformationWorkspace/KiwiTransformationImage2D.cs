using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiTransformationImage2D : Resource
{
    [Export] public long version { get; set; } = 1;
    [Export] public Vector2I canvas_size { get; set; } = new Vector2I(1280,720);
    [Export] public double duration { get; set; } = 3.0;
    [Export] public Godot.Collections.Array<KiwiTransformationComponent> components { get; set; } = new();
    [Export] public Settings workspace_state { get; set; } = new();
    [Export] public Settings metadata { get; set; } = new();
    [Export] public byte[] preview_png { get; set; } = Array.Empty<byte>();
    [Export] public Godot.Collections.Array<Settings> component_events { get; set; } = new();
    private readonly TransformationResourceOperations _operations = new();
    public KiwiTransformationComponent? component(string id) => _operations.lookup(this, "components", id) as KiwiTransformationComponent;
    public KiwiTransformationImage2D snapshot() => (KiwiTransformationImage2D)_operations.snapshot(this);
    public static KiwiTransformationImage2D blank() => blank(new Vector2I(1280, 720));
    public static KiwiTransformationImage2D blank(Vector2I size) => (KiwiTransformationImage2D)new TransformationResourceOperations().blank(size);
    public static KiwiTransformationComponent make_component(Vector2I size) => make_component(size, "Component");
    public static KiwiTransformationComponent make_component(Vector2I size, string title) => (KiwiTransformationComponent)new TransformationResourceOperations().make_component(size, title);
    public string[] validate() => _operations.validate(this);
    public Texture2D? thumbnail() => _operations.thumbnail(this);

}
