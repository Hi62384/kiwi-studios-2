using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
[Tool]
public partial class SharedControlOperations : RefCounted
{
    private static T Field<T>(Control owner, string name) where T : GodotObject => (T)owner.Get(name).AsGodotObject();
    public void expandable_property(Control owner, string name, bool notify)
    {
        if (!owner.IsNodeReady()) return;
        switch (name)
        {
            case "expanded":
                bool expanded = owner.Get("expanded").AsBool(); Field<TextureRect>(owner, "_expandable_icon").Texture = GD.Load<Texture2D>(expanded ? "uid://ciadauk2mpudq" : "uid://bdblvy7bf8xgn"); Field<Control>(owner, "_children_container").Visible = expanded; if (notify) owner.EmitSignal("toggled", expanded); break;
            case "icon": Field<TextureRect>(owner, "_main_icon").Texture = owner.Get("icon").As<Texture2D>(); break;
            case "text": var label = Field<Label>(owner, "_label"); label.Text = owner.Get("text").AsString(); label.TooltipText = label.Text; break;
            case "label_settings": Field<Label>(owner, "_label").LabelSettings = owner.Get("label_settings").As<LabelSettings>(); break;
            case "panel_stylebox": var style = owner.Get("panel_stylebox").As<StyleBox>(); var panel = Field<Control>(owner, "_panel"); if (style == null) panel.RemoveThemeStyleboxOverride("panel"); else panel.AddThemeStyleboxOverride("panel", style); break;
            case "cover_colorrect_color": Field<ColorRect>(owner, "_cover_color_rect").Color = owner.Get("cover_colorrect_color").AsColor(); break;
        }
    }
    public void expandable_ready(Control owner)
    {
        foreach (string name in new[] { "icon", "text", "expanded" }) expandable_property(owner, name, false);
        Field<Button>(owner, "_expandable_icon_button").Pressed += () => { if (GodotObject.IsInstanceValid(owner)) owner.Set("expanded", !owner.Get("expanded").AsBool()); };
    }
    public Control expandable_control(Control owner, string name) => Field<Control>(owner, name);
    public void add_child_in_expand(Control owner, Node child) => Field<VBoxContainer>(owner, "_children_container").AddChild(child);
    public void action_panel_property(Control owner, string name)
    {
        switch (name)
        {
            case "panel_icon": Field<TextureRect>(owner, "icon_texture_rect").Texture = owner.Get("panel_icon").As<Texture2D>(); break;
            case "panel_text": Field<Label>(owner, "text_label").Text = owner.Get("panel_text").AsString(); break;
            case "key_shortcut_text": Field<Label>(owner, "key_shortcut").Text = owner.Get("key_shortcut_text").AsString(); break;
            case "has_more_options": Field<Button>(owner, "more_options_button").Visible = owner.Get("has_more_options").AsBool(); break;
        }
    }
    public void dialogue_ready(Control owner)
    {
        Field<Button>(owner, "_create_new_button").Connect("mouse_entered", new Callable(owner, "_show_external_panels"));
        foreach (var value in owner.Get("_buttons_to_hide_external_panels").AsGodotArray()) value.As<Button>().Connect("mouse_entered", new Callable(owner, "_hide_external_panels")); fully_visible(owner);
    }
    public void external_panels(Control owner, bool visible) => Field<Control>(owner, "_create_new_panel").Visible = visible;
    public void fully_visible(Control owner) => owner.GlobalPosition = owner.GlobalPosition.Clamp(Vector2.Zero, (owner.GetViewportRect().Size - owner.Size).Max(Vector2.Zero));
    public bool dismiss_dialogue() => Input.IsActionJustReleased("left_click") || Input.IsActionJustPressed("right_click");
    public void chooser_ready(Control owner)
    {
        Field<Button>(owner, "close_button").Connect("pressed", new Callable(owner, "_cancel_params")); Field<Button>(owner, "select_button").Connect("pressed", new Callable(owner, "_confirm_params"));
    }
    public void chooser_decision(Control owner, bool cancel) => owner.Get("_state").AsGodotDictionary()[cancel ? "badboy" : "finished"] = true;
    public Settings begin_params(Control owner)
    {
        owner.Visible = true; long revision = owner.Get("_param_revision").AsInt64() + 1; owner.Set("_param_revision", revision); var state = new Settings { ["finished"] = false, ["badboy"] = false, ["revision"] = revision }; owner.Set("_state", state); return state;
    }
    public bool params_done(Control owner, Settings state) => !owner.IsInsideTree() || state["revision"].AsInt64() != owner.Get("_param_revision").AsInt64() || state["badboy"].AsBool() || state["finished"].AsBool();
    public Settings finish_params(Control owner, Settings state)
    {
        var result = new Settings(); if (state["revision"].AsInt64() != owner.Get("_param_revision").AsInt64()) return result; owner.Visible = false; if (state["badboy"].AsBool()) return result;
        foreach (var value in owner.Get("mappings").AsGodotArray()) { var mapping = value.As<Resource>(); result[mapping.Get("tag")] = owner.GetNode(mapping.Get("node").AsNodePath()).Get(mapping.Get("property_name").AsStringName()); } return result;
    }
    public void delete_children(Node parent) { foreach (Node child in parent.GetChildren()) child.QueueFree(); }
    public bool compare(Resource condition, Variant value)
    {
        var values = condition.Get("compare_value").AsGodotArray(); int operation = condition.Get("condition").AsInt32(); if (values.Count == 0 || operation < 0 || operation >= 6) return false;
        using var expression = new Expression(); expression.Parse("a " + new[] { "==", ">", "<", ">=", "<=", "!=" }[operation] + " b", new[] { "a", "b" }); var result = expression.Execute(new Godot.Collections.Array { value, values[0] }); return !expression.HasExecuteFailed() && result.AsBool();
    }
}
