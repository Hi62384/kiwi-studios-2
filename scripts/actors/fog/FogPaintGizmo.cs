using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class FogPaintGizmo : RefCounted
{
    public static Script Field => GD.Load<Script>("res://scripts/actors/fog/fog_field.gd");
    public Node? spatial {get;set;}
    public ActorData? owner_actor {get;set;}
    public ActorObjectData? @object {get;set;}
    public Settings before {get;set;} = new();
    public bool painting {get;set;}
    public Vector3 last {get;set;} = Vector3.Inf;
    public Vector3 cursor {get;set;} = Vector3.Inf;
    private readonly FogPaintGizmoOperations _operations = new();
    public bool active() => _operations.active(this);
    public ActorObjectData? field() => _operations.field(this) as ActorObjectData;
    public void tick() => _operations.tick(this);
    public Vector3 point(Vector2 screen) => _operations.point(this,screen);
    public void draw() => _operations.draw(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
    public void dab(Vector2 screen) => dab(screen,false);
    public void dab(Vector2 screen,bool subtract) => _operations.dab(this,screen,subtract);
    public void finish() => finish(false);
    public void finish(bool cancel) => _operations.finish(this,cancel);
}
