using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class ActorSkeletonGizmo : RefCounted
{
    public Node? spatial {get;set;}
    public Settings before {get;set;} = new();
    public Vector3 original {get;set;}
    public Vector3 final {get;set;}
    public ActorSkeletonRigRuntime? drag_rig {get;set;}
    public int drag_bone {get;set;} = -1;
    public string channel {get;set;} = "position";
    public Basis parent_basis {get;set;} = Basis.Identity;
    public string selection {get;set;} = "";
    public double time {get;set;}
    private readonly ActorSkeletonGizmoOperations _operations = new();
    public ActorSkeletonRigRuntime? runtime() => _operations.runtime(this) as ActorSkeletonRigRuntime;
    public bool active() => _operations.active(this);
    public int selected() => _operations.selected(this);
    public Transform3D transform() => _operations.transform(this);
    public void select_bone(int index) => _operations.select_bone(this,index);
    public Rect2 toolbar_rect(int index) => _operations.toolbar_rect(index);
    public void draw() => _operations.draw(this);
    public int pick(Vector2 point) => pick(point,false);
    public int pick(Vector2 point,bool joints_only) => _operations.pick(this,point,joints_only);
    public bool begin() => _operations.begin(this);
    public void update(Vector2 point,bool snap) => _operations.update(this,point,snap);
    public void finish() => finish(false);
    public void finish(bool cancel) => _operations.finish(this,cancel);
    public void sync() => _operations.sync(this);
    public void reset() => _operations.reset(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
}
