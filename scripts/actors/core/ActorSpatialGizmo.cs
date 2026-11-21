using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;
[GlobalClass]
public partial class ActorSpatialGizmo : Node
{
    public Variant gizmo {get;set;}
    public Node? editor {get;set;}
    public string mode {get;set;} = "move";
    public ActorPropertyBatch batch {get;set;} = new();
    public Godot.Collections.Array<Settings> before {get;set;} = new();
    public Settings originals {get;set;} = new();
    public Settings final_values {get;set;} = new();
    public Godot.Collections.Array<string> selection {get;set;} = new();
    public double sample_time {get;set;}
    public int drag_axis {get;set;} = -1;
    public Vector2 start_mouse {get;set;}
    public Vector3 pivot {get;set;}
    public Vector3 axis {get;set;} = Vector3.Right;
    public Vector3 plane_normal {get;set;} = Vector3.Forward;
    public Vector3 start_point {get;set;}
    public Vector3 start_vector {get;set;} = Vector3.Right;
    public double drag_length {get;set;} = 1;
    public ActorSkeletonGizmo rig {get;set;} = new();
    public PhysicsPinGizmo physics_pins {get;set;} = new();
    public DestructionGizmo damage {get;set;} = new();
    public StructureGizmo structure {get;set;} = new();
    public FogPaintGizmo fog_paint {get;set;} = new();
    public static readonly Color[] COLORS = {new("f27e81"),new("84dc9e"),new("80baff")};
    public static readonly int[][] EDGES = {new[]{0,1},new[]{0,2},new[]{0,4},new[]{1,3},new[]{1,5},new[]{2,3},new[]{2,6},new[]{3,7},new[]{4,5},new[]{4,6},new[]{5,7},new[]{6,7}};
    public static readonly StringName[] PROXIES = {"point_3d","remote_transform","light_3d","directional_light","skeleton_rig","powder","fog_volume","global_fog"};
    private readonly ActorSpatialGizmoOperations _operations = new();
    public override void _Ready() => _operations.ready(this);
    public Camera3D? camera() => _operations.camera(this);
    public bool enabled() => _operations.enabled(this);
    public ActorRuntime? primary() => _operations.primary(this) as ActorRuntime;
    public Vector2 project(Vector3 point) => _operations.project(this,point);
    public bool in_picture(Vector2 point) => _operations.in_picture(this,point);
    public void _visuals(Node node,Godot.Collections.Array<VisualInstance3D> result) => _visuals(node,result,true);
    public void _visuals(Node node,Godot.Collections.Array<VisualInstance3D> result,bool root)
    {using var values=Variant.From(result); _operations.collect_visuals(this,node,values.AsGodotArray(),root);}
    public Godot.Collections.Array<VisualInstance3D> visuals(ActorRuntime runtime) => new(_operations.visuals(this,runtime));
    public Settings bounds(ActorRuntime runtime) => _operations.bounds(this,runtime);
    public Godot.Collections.Array<Vector2[]> box_lines(ActorRuntime runtime) => new(_operations.box_lines(this,runtime));
    public Settings _ray(Vector2 point) => _operations.ray(this,point);
    public Variant _hit_visual(VisualInstance3D visual,Settings ray) => _operations.hit_visual(visual,ray);
    public string pick(Vector2 point) => _operations.pick(this,point);
    public Settings geometry() => _operations.geometry(this);
    public Rect2 toolbar_rect(int index) => _operations.toolbar_rect(index);
    public int handle_at(Vector2 point,Settings data) => _operations.handle_at(this,point,data);
    public void draw() => _operations.draw(this);
    public Variant _plane_hit(Vector2 point) => _operations.plane_hit(this,point);
    public bool begin(int index,Vector2 point) => _operations.begin(this,index,point);
    public void update(Vector2 point) => update(point,false);
    public void update(Vector2 point,bool snap) => _operations.update(this,point,snap);
    public void finish() => finish(false);
    public void finish(bool cancel) => _operations.finish(this,cancel);
    public void sync() => _operations.sync(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
    public void hover(Vector2 point) => _operations.hover(this,point);
    public override void _ExitTree() => _operations.exit_tree(this);
}
