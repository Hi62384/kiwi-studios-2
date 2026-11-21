using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class ActorUIGizmo : Control
{
    public Node? editor {get;set;}
    public TextureRect? display {get;set;}
    public StringName drag_key {get;set;} = "position";
    public ActorPropertyBatch batch {get;set;} = new();
    public Godot.Collections.Array<Settings> before {get;set;} = new();
    public Vector2 start_mouse {get;set;}
    public Vector2 center {get;set;}
    public Settings parents {get;set;} = new();
    public Settings origins {get;set;} = new();
    public Settings final_values {get;set;} = new();
    public Vector2 resize_axis {get;set;} = Vector2.One;
    public Transform2D visual_transform {get;set;} = Transform2D.Identity;
    public SubViewport? camera_preview {get;set;}
    public Camera3D? preview_lens {get;set;}
    public ColorRect? preview_shader_overlay {get;set;}
    public bool preview_active {get;set;}
    public Settings preview_clones {get;set;} = new();
    public Vector2 preview_position {get;set;} = new(-1,-1);
    public bool preview_dragging {get;set;}
    public Vector2 preview_drag_delta {get;set;}
    public bool preview_user_moved {get;set;}
    public ActorSpatialGizmo spatial {get;set;} = new();
    private readonly ActorUIGizmoOperations _operations = new();
    public Transform2D display_transform() => _operations.display_transform(this);
    public Vector2 scene_point(Vector2 point) => _operations.scene_point(this,point);
    public Settings handle_points(ActorUIRuntime runtime) => _operations.handle_points(this,runtime);
    public override void _Ready() => _operations.ready(this);
    public ActorUIRuntime? selected_runtime() => _operations.selected_runtime(this) as ActorUIRuntime;
    public Vector2[] corners(ActorUIRuntime runtime) => _operations.corners(this,runtime);
    public override void _Process(double delta) => _operations.process(this);
    public void _sync_preview_2d() => _operations.sync_preview_2d(this);
    public Rect2 _preview_rect() => _operations.preview_rect(this);
    public override void _Draw() => _operations.draw(this);
    public void begin_drag(StringName key,Vector2 position) => _operations.begin_drag(this,key,position);
    public void update_drag(Vector2 position) => _operations.update_drag(this,position);
    public void finish_drag() => finish_drag(false);
    public void finish_drag(bool cancel) => _operations.finish_drag(this,cancel);
    public override void _GuiInput(InputEvent input) => _operations.gui_input(this,input);
}
