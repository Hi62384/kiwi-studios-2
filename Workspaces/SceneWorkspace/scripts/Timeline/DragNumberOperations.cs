using Godot;
using System;
public partial class DragNumberOperations : RefCounted
{
    public void ready(SpinBox owner) { owner.GetLineEdit().MouseDefaultCursorShape = Control.CursorShape.Hsize; owner.TooltipText = "Drag: 0.1 • Ctrl: 1 • Shift: 0.01. Click to type."; owner.GetLineEdit().Connect("gui_input", new Callable(owner, "_line_edit_input")); }
    public void line_edit_input(SpinBox owner, InputEvent input)
    {
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left, Pressed: true } mouse && owner.Editable) { begin_drag(owner, owner.GetLineEdit().GetGlobalTransformWithCanvas() * mouse.Position); owner.GetLineEdit().AcceptEvent(); }
    }
    public void begin_drag(SpinBox owner, Vector2 position) { owner.Set("_pressed", true); owner.Set("_origin", owner.Value); owner.Set("_press_x", position.X); owner.Set("_last_x", position.X); owner.Set("_remainder", 0.0); }
    public void input(SpinBox owner, InputEvent input)
    {
        bool pressed = owner.Get("_pressed").AsBool();
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left, Pressed: false } && pressed)
        {
            if (owner.Get("dragging").AsBool()) finish_drag(owner); else { owner.Set("_pressed", false); owner.GetLineEdit().GrabFocus(); owner.GetLineEdit().SelectAll(); } owner.GetViewport().SetInputAsHandled();
        }
        else if (input is InputEventMouseMotion mouse && pressed)
        {
            if (!owner.Get("dragging").AsBool() && Math.Abs(mouse.Position.X - owner.Get("_press_x").AsDouble()) >= 4) { owner.Set("dragging", true); owner.EmitSignal("interaction_started"); }
            if (owner.Get("dragging").AsBool()) { drag_pixels(owner, mouse.Position.X - owner.Get("_last_x").AsDouble(), mouse.CtrlPressed, mouse.ShiftPressed); owner.Set("_last_x", mouse.Position.X); wrap_pointer(owner, mouse.Position); } owner.GetViewport().SetInputAsHandled();
        }
        else if (input is InputEventKey { Pressed: true } key && pressed) { if (key.Keycode == Key.Escape) cancel_drag(owner); owner.GetViewport().SetInputAsHandled(); }
    }
    public void drag_pixels(SpinBox owner, double pixels, bool ctrl, bool shift)
    {
        double remainder = owner.Get("_remainder").AsDouble() + pixels; int ticks = (int)(remainder / 4); owner.Set("_remainder", remainder - ticks * 4);
        bool integerStep = owner.Step >= 1 && Mathf.IsEqualApprox(owner.Step, Math.Round(owner.Step)); double increment = integerStep ? owner.Step : shift ? .01 : ctrl ? 1 : .1;
        owner.SetValueNoSignal(owner.Value + ticks * increment); if (ticks != 0) owner.EmitSignal("preview_changed", owner.Value);
    }
    public Vector2 wrap_target(Vector2 position, Rect2 bounds)
    {
        if (bounds.Size.X < 12 || bounds.Size.Y < 12) return position; var target = position;
        if (position.X >= bounds.End.X - 2) target.X = bounds.Position.X + 4; else if (position.X <= bounds.Position.X + 2) target.X = bounds.End.X - 4;
        if (position.Y >= bounds.End.Y - 2) target.Y = bounds.Position.Y + 4; else if (position.Y <= bounds.Position.Y + 2) target.Y = bounds.End.Y - 4; return target;
    }
    public void wrap_pointer(SpinBox owner, Vector2 position)
    {
        var target = wrap_target(position, owner.GetViewport().GetVisibleRect()); if (target == position) return; owner.Set("_last_x", target.X); if (DisplayServer.GetName() != "headless") owner.GetViewport().WarpMouse(target);
    }
    public void finish_drag(SpinBox owner)
    {
        double value = owner.Value; owner.Set("_pressed", false); owner.Set("dragging", false); owner.EmitSignal("interaction_ended"); if (!Mathf.IsEqualApprox(owner.Get("_origin").AsDouble(), value)) owner.EmitSignal("drag_committed", value);
    }
    public void cancel_drag(SpinBox owner)
    {
        bool dragging = owner.Get("dragging").AsBool(); if (owner.Get("_pressed").AsBool()) owner.SetValueNoSignal(owner.Get("_origin").AsDouble()); owner.Set("_pressed", false); owner.Set("dragging", false); owner.EmitSignal("interaction_ended"); if (dragging) owner.EmitSignal("drag_cancelled");
    }
}
