using Godot;
public partial class LiveColorPickerOperations : RefCounted
{
    public void ready(ColorPickerButton owner)
    {
        var swatch = new ColorRect { Name = "ColorSwatch", MouseFilter = Control.MouseFilterEnum.Ignore, Color = owner.Color }; swatch.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); swatch.OffsetLeft = 7; swatch.OffsetTop = 6; swatch.OffsetRight = -7; swatch.OffsetBottom = -6; owner.Set("_swatch", swatch); owner.AddChild(swatch); owner.MoveChild(swatch, 0); owner.Connect("color_changed", new Callable(owner, "_on_color_changed")); owner.Connect("popup_closed", new Callable(owner, "_on_popup_closed")); owner.Connect("pressed", new Callable(owner, "begin_session")); owner.TooltipText = "Changes preview live. Each drag is one undo step.";
    }
    public void input(ColorPickerButton owner, InputEvent input) { if (input is InputEventKey { Pressed: true, Keycode: Key.Escape } && owner.Get("dragging").AsBool()) cancel_drag(owner); }
    public void process(ColorPickerButton owner) { if (owner.Get("dragging").AsBool() && !Input.IsMouseButtonPressed(MouseButton.Left)) finish_drag(owner); }
    public void begin_session(ColorPickerButton owner) { owner.Set("_session_active", true); owner.Set("_pending_origin", owner.Color); }
    public void begin_drag(ColorPickerButton owner)
    {
        if (owner.Get("dragging").AsBool()) return; owner.Set("dragging", true); owner.Set("_origin", owner.Get("_session_active").AsBool() ? owner.Get("_pending_origin") : owner.Color); owner.EmitSignal("interaction_started");
    }
    public void on_color_changed(ColorPickerButton owner, Color value)
    {
        update_swatch(owner, value); if (owner.Get("_suppress_preview").AsBool() || !owner.GetPopup().Visible) return; if (!owner.Get("dragging").AsBool()) begin_drag(owner); owner.EmitSignal("preview_changed", value);
    }
    public void on_popup_closed(ColorPickerButton owner) { if (owner.Get("dragging").AsBool()) finish_drag(owner); owner.EmitSignal("interaction_ended"); owner.Set("_session_active", false); }
    public void finish_drag(ColorPickerButton owner)
    {
        if (!owner.Get("dragging").AsBool()) return; var original = owner.Get("_origin").AsColor(); var value = owner.Color; owner.Set("dragging", false); owner.Set("_pending_origin", value); owner.EmitSignal("interaction_ended"); if (original != value) owner.EmitSignal("drag_committed", original, value);
    }
    public void cancel_drag(ColorPickerButton owner)
    {
        if (!owner.Get("dragging").AsBool()) return; var original = owner.Get("_origin").AsColor(); owner.Set("dragging", false); set_color_silent(owner, original); owner.Set("_pending_origin", original); owner.EmitSignal("interaction_ended"); owner.EmitSignal("drag_cancelled", original);
    }
    public void set_color_silent(ColorPickerButton owner, Color value)
    {
        owner.Set("_suppress_preview", true); try { owner.Color = value; update_swatch(owner, value); } finally { owner.Set("_suppress_preview", false); } if (!owner.Get("dragging").AsBool()) owner.Set("_pending_origin", value);
    }
    public void update_swatch(ColorPickerButton owner, Color value) { var swatch = owner.Get("_swatch").As<ColorRect>(); if (GodotObject.IsInstanceValid(swatch)) swatch!.Color = value; }
}
