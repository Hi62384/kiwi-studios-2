using Godot;
using System.Globalization;
public partial class ViewportFocusableInputOperations : RefCounted
{
    private readonly FocusableInputOperations _focus = new();
    private readonly FreecamOperations _camera = new();
    private static Node3D Camera(Control owner) => owner.Get("freecam").As<Node3D>();
    public void process(Control owner, double delta)
    {
        if (!Input.IsActionPressed("right_click") || !_focus.is_focused(owner)) return;
        foreach (var pair in new[] { ("move_forward", "forward"), ("move_backwards", "backward"), ("move_left", "left"), ("move_right", "right"), ("move_up", "up"), ("move_down", "down") }) if (Input.IsActionPressed(pair.Item1)) _camera.move(Camera(owner), pair.Item2, delta);
    }
    public void focused_input(Control owner, InputEvent input)
    {
        if (!Input.IsActionPressed("right_click")) return;
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Right, Pressed: true }) owner.GetViewport().GuiReleaseFocus();
        if (input is InputEventMouseMotion mouse) { _camera.look_up(Camera(owner), mouse.Relative.Y); _camera.look_left(Camera(owner), mouse.Relative.X); }
        if (Input.IsActionJustPressed("scroll_up")) { _camera.increase_speed(Camera(owner), .1); owner.Call("_display_freecam_speed"); }
        else if (Input.IsActionJustPressed("scroll_down")) { _camera.increase_speed(Camera(owner), -.1); owner.Call("_display_freecam_speed"); }
    }
    public long display_speed(Control owner)
    {
        long id = owner.Get("_speed_display_id").AsInt64() + 1; owner.Set("_speed_display_id", id); double speed = Camera(owner).Get("speed").AsDouble(); var bar = owner.Get("freecam_speed_bar").As<ProgressBar>(); bar.Value = speed / 1000; owner.Get("freecam_speed_label").As<Label>().Text = "Freecam Speed: " + Mathf.Snapped(speed, .1).ToString("0.0", CultureInfo.InvariantCulture) + "m/s"; bar.Visible = true; return id;
    }
    public void finish_display(Control owner, long id) { if (owner.Get("_speed_display_id").AsInt64() == id) owner.Get("freecam_speed_bar").As<ProgressBar>().Visible = false; }
}
