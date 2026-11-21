using Godot;
[GlobalClass]
public partial class PhysicsPinGizmo : RefCounted
{
    public Node? spatial {get;set;}
    private readonly PhysicsPinGizmoOperations _operations = new();
    public bool active() => _operations.active(this);
    public Vector3[] points() => _operations.points(this);
    public void draw() => _operations.draw(this);
    public bool handle_event(InputEvent input) => _operations.handle_event(this,input);
}
