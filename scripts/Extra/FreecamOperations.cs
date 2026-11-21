using Godot;
using System;
public partial class FreecamOperations : RefCounted
{
    public double effective_speed(Node3D owner, double delta)
    {
        double speed = owner.Get("speed").AsDouble() * delta; if (Input.IsActionPressed("shift")) speed *= 2; if (Input.IsActionPressed("ctrl")) speed /= 2; return speed;
    }
    public void move(Node3D owner, string direction, double delta)
    {
        var head = owner.Get("head").As<Node3D>(); var camera = owner.Get("camera").As<Camera3D>();
        var axis = direction switch { "forward" => -head.Transform.Basis.Z, "backward" => head.Transform.Basis.Z, "left" => -head.Transform.Basis.X, "right" => head.Transform.Basis.X, "up" => camera.GlobalTransform.Basis.Y, "down" => -camera.GlobalTransform.Basis.Y, _ => Vector3.Zero }; owner.Position += axis * (float)effective_speed(owner, delta);
    }
    public void look_left(Node3D owner, double amount) { var head = owner.Get("head").As<Node3D>(); var rotation = head.Rotation; rotation.Y -= (float)(amount * .01); head.Rotation = rotation; }
    public void look_up(Node3D owner, double amount) { var camera = owner.Get("camera").As<Camera3D>(); var rotation = camera.Rotation; rotation.X = Math.Clamp(rotation.X - (float)(amount * .01), -Mathf.Pi, Mathf.Pi); camera.Rotation = rotation; }
    public void increase_speed(Node3D owner, double amount) => owner.Set("speed", Math.Clamp(owner.Get("speed").AsDouble() * (1 + amount), 0, 1000));
}
