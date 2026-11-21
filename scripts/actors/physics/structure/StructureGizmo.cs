using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class StructureGizmo : RefCounted
{
    public Node? spatial {get;set;}
    public ActorData? actor {get;set;}
    public Settings before {get;set;} = new();
    public string field {get;set;} = "pivot";
    public string selected {get;set;} = "";
    public Plane plane {get;set;}
    public Vector3 offset {get;set;}
    private readonly StructureGizmoOperations _operations = new();
    public bool enabled(ActorData data) => _operations.enabled(this,data);
    public Vector3 physical_point(RefCounted controller,string owner,Vector3 point,Transform3D fallback) => _operations.physical_point(controller,owner,point,fallback);
    public bool active() => _operations.active(this);
    public void draw() => _operations.draw(this);
    public void cancel() => _operations.cancel(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
}
