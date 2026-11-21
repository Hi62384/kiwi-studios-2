using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ActorSceneTreeOperations
{
    private static Control? Editor(Tree owner) => owner.GetTree().GetFirstNodeInGroup("actor_timeline_editors") as Control;
    private static bool SameModel(Control? editor, RefCounted model) => editor != null && editor.Get("model").AsGodotObject() == model;
    public void input(Tree owner, InputEvent input)
    {
        var model = Model(owner);
        if (!owner.HasFocus() || input is not InputEventKey || model == null) return;
        var editor = Editor(owner); if (SameModel(editor, model)) editor!.Call("handle_actor_shortcut", input);
    }
    public void gui_input(Tree owner, InputEvent input)
    {
        var model = Model(owner);
        if (input is InputEventKey && model != null)
        {
            var editor = Editor(owner);
            if (SameModel(editor, model) && editor!.Call("handle_actor_shortcut", input).AsBool()) owner.AcceptEvent();
            return;
        }
        if (input is InputEventMouseButton { Pressed: true }) FocusableKeyInput.current_focused_instance = null;
        if (model == null || owner.Get("_rebuilding").AsBool() || input is not InputEventMouseButton { Pressed: true } mouse) return;
        var item = owner.GetItemAtPosition(mouse.Position); string actorId = ItemId(item); var clip = Clip(model, actorId);
        bool section = actorId.StartsWith("section:", StringComparison.Ordinal);
        if (mouse.ButtonIndex == MouseButton.Left && section)
        {
            model.Call("select_section", actorId[8..]); owner.Set("_selection_anchor", ""); return;
        }
        if (mouse.ButtonIndex == MouseButton.Left && clip != null)
        {
            var actor = Actor(model, actorId);
            if (actor != null && actor.Get("section_id").AsString() != model.Get("selected_section_id").AsString()) model.Call("select_section", actor.Get("section_id"));
            if (mouse.ShiftPressed) select_range(owner, actorId);
            else
            {
                model.Call("select", Id(clip), mouse.CtrlPressed || model.Call("is_selected", Id(clip)).AsBool());
                owner.Set("_selection_anchor", actorId);
            }
        }
        else if (mouse.ButtonIndex == MouseButton.Right && clip != null)
        {
            model.Call("select", Id(clip), model.Call("is_selected", Id(clip))); owner.Set("_selection_anchor", actorId);
            Editor(owner)?.Call("_show_context_menu", mouse.GlobalPosition, true, clip.Get("start_time"), clip.Get("layer")); owner.AcceptEvent();
        }
        else if (mouse.ButtonIndex == MouseButton.Right && (item == owner.GetRoot() || section))
        {
            if (section) model.Call("select_section", actorId[8..]);
            var editor = Editor(owner);
            if (editor != null) editor.Call("_show_context_menu", mouse.GlobalPosition, false, editor.Get("canvas").AsGodotObject().Get("playhead"), editor.Get("model").AsGodotObject().Get("selected_layer"), section ? item!.GetText(0) : "SCENE", section ? actorId[8..] : "");
            owner.AcceptEvent();
        }
    }
    public Godot.Collections.Array<string> visible_actor_ids(Tree owner)
    {
        var result = new Godot.Collections.Array<string>(); var model = Model(owner); if (model == null) return result;
        for (var item = owner.GetRoot()?.GetNextVisible(); item != null; item = item.GetNextVisible())
        {
            string id = ItemId(item); var actor = Actor(model, id);
            if (actor != null && actor.Get("section_id").AsString() == model.Get("selected_section_id").AsString()) result.Add(id);
        }
        return result;
    }
    public void select_range(Tree owner, string clickedId)
    {
        var model = Model(owner); if (model == null) return;
        var visible = visible_actor_ids(owner); int anchor = visible.IndexOf(owner.Get("_selection_anchor").AsString()), clicked = visible.IndexOf(clickedId);
        if (anchor < 0 || clicked < 0)
        {
            var clip = Clip(model, clickedId); if (clip != null) model.Call("select", Id(clip)); owner.Set("_selection_anchor", clickedId); return;
        }
        var ids = new Godot.Collections.Array<string>();
        for (int i = Math.Min(anchor, clicked); i <= Math.Max(anchor, clicked); i++) { var clip = Clip(model, visible[i]); if (clip != null) ids.Add(Id(clip)); }
        var primary = Clip(model, clickedId); model.Call("set_selection", ids, primary == null ? "" : Id(primary));
    }
    public Variant get_drag_data(Tree owner, Vector2 position)
    {
        var model = Model(owner); if (model == null) return default;
        string actorId = ItemId(owner.GetItemAtPosition(position)); var actor = Actor(model, actorId); if (actor == null) return default;
        var preview = new Label { Text = "  " + actor.Get("display_name").AsString() + "  " }; preview.AddThemeColorOverride("font_color", new Color("eaf8f4")); owner.SetDragPreview(preview);
        var ids = new Godot.Collections.Array<string> { actorId }; var clip = Clip(model, actorId);
        if (clip != null && model.Call("is_selected", Id(clip)).AsBool())
        {
            ids.Clear(); foreach (var selected in model.Call("selected_actors").AsGodotArray()) ids.Add(Id(selected.AsGodotObject()));
        }
        return new Settings { ["type"] = "actor_scene_tree", ["actor_id"] = actorId, ["actor_ids"] = ids };
    }
    private static GArray DragIds(Settings data) => data.TryGetValue("actor_ids", out var ids) && ids.VariantType == Variant.Type.Array ? ids.AsGodotArray() : new GArray { data.TryGetValue("actor_id", out var id) ? id.AsString() : "" };
    public bool can_drop_data(Tree owner, Vector2 position, Variant data)
    {
        var model = Model(owner);
        if (model == null || data.VariantType != Variant.Type.Dictionary) return false;
        var dict = data.AsGodotDictionary(); if (!dict.TryGetValue("type", out var kind) || kind.AsString() != "actor_scene_tree") return false;
        var item = owner.GetItemAtPosition(position); if (item == null) return false;
        string parent = ItemId(item);
        if (parent.StartsWith("section:", StringComparison.Ordinal)) return model.Call("section_for_id", parent[8..]).As<Resource>() != null;
        var ids = DragIds(dict);
        if (ids.Contains(parent)) return false;
        return ids.All(id => id.AsString() != parent && model.Call("can_set_parent", id.AsString(), parent).AsBool());
    }
    public void drop_data(Tree owner, Vector2 position, Variant data)
    {
        if (!can_drop_data(owner, position, data)) return;
        var model = Model(owner)!; string parent = ItemId(owner.GetItemAtPosition(position)); var ids = new Godot.Collections.Array<string>();
        foreach (var id in DragIds(data.AsGodotDictionary())) ids.Add(id.AsString());
        if (parent.StartsWith("section:", StringComparison.Ordinal)) model.Call("move_to_section", ids, parent[8..]);
        else if (parent == "") model.Call("unparent_many", ids);
        else if (ids.Count == 1) model.Call("set_parent", ids[0], parent);
        else model.Call("parent_many", ids, parent);
    }
}
