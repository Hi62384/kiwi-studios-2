using Godot;
using System;
public partial class FocusableInputOperations : RefCounted
{
    public void ready(Control owner) => owner.MouseFilter = Control.MouseFilterEnum.Ignore;
    public bool mouse_inside(Control owner) => new Rect2(owner.GlobalPosition, owner.Size).HasPoint(owner.GetViewport().GetMousePosition());
    public bool is_focused(Control owner) => FocusableKeyInput.current_focused_instance == owner;
    public void input(Control owner, InputEvent input)
    {
        if (!owner.IsVisibleInTree()) return;
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Right, Pressed: true } && mouse_inside(owner)) { FocusableKeyInput.current_focused_instance = owner as FocusableKeyInput; owner.GetViewport().GuiReleaseFocus(); }
        if ((Input.IsActionJustPressed("left_click") || Input.IsActionJustPressed("right_click")) && mouse_inside(owner)) FocusableKeyInput.current_focused_instance = owner as FocusableKeyInput;
        if (is_focused(owner)) owner.Call("_focused_input", input);
    }
    public void exit_tree(Control owner) { if (is_focused(owner)) FocusableKeyInput.current_focused_instance = null; }
}
