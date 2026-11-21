using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class DestructionGizmo : RefCounted
{
    public Node? spatial {get;set;}
    public Settings before {get;set;} = new();
    public Godot.Collections.Array<ActorAnimationTrack> tracks {get;set;} = new();
    public ActorData? actor {get;set;}
    public string selected {get;set;} = "";
    public Plane plane {get;set;}
    public Vector3 offset {get;set;}
    public bool fragment_drag {get;set;}
    public Vector3 fragment_origin {get;set;}
    public Settings fragment_rule_before {get;set;} = new();
    private readonly DestructionGizmoOperations _operations = new();
    public bool available() => _operations.available(this);
    public bool active() => _operations.active(this);
    public Settings selected_operation() => _operations.selected_operation(this);
    public void draw() => _operations.draw(this);
    public void draw_pattern() => _operations.draw_pattern(this);
    public void draw_fragments() => _operations.draw_fragments(this);
    public void restore(Settings values,Godot.Collections.Array<ActorAnimationTrack> animation)
    {using var array=Variant.From(animation); _operations.restore(this,values,array.AsGodotArray());}
    public void cancel() => _operations.cancel(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
    public bool fragment_event(InputEvent input,ActorData data) => _operations.fragment_event(this,input,data);
}
