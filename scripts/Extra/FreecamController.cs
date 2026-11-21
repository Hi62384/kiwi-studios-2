using Godot;

[GlobalClass]
public partial class FreecamController : Node3D
{
    public const double SENSITIVITY = .01;
    public const int MAX_SPEED = 1000;
    public Node3D? head { get; set; }
    public Camera3D? camera { get; set; }
    public double speed { get; set; } = 5;
    private readonly FreecamOperations _operations = new();
    public override void _Ready() { head = GetNode<Node3D>("Head"); camera = GetNode<Camera3D>("Head/Camera3D"); }
    public double _get_effective_speed(double delta) => _operations.effective_speed(this, delta);
    public void move_forward(double delta) => _operations.move(this, "forward", delta);
    public void move_backward(double delta) => _operations.move(this, "backward", delta);
    public void move_left(double delta) => _operations.move(this, "left", delta);
    public void move_right(double delta) => _operations.move(this, "right", delta);
    public void move_up(double delta) => _operations.move(this, "up", delta);
    public void move_down(double delta) => _operations.move(this, "down", delta);
    public void look_left(double amount) => _operations.look_left(this, amount);
    public void look_up(double amount) => _operations.look_up(this, amount);
    public void increase_speed(double amount) => _operations.increase_speed(this, amount);
}
