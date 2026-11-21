using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ActorSceneTreeOperations : RefCounted
{
    private static RefCounted? Model(Tree owner) => owner.Get("model").As<RefCounted>();
    private static Settings Items(Tree owner) => owner.Get("_items").AsGodotDictionary();
    private static GArray Actors(RefCounted model) => model.Get("actors").AsGodotArray();
    private static Resource? Actor(RefCounted model, string id) => model.Call("actor_for_id", id).As<Resource>();
    private static Resource? Clip(RefCounted model, string id) => model.Call("clip_for_actor_id", id).As<Resource>();
    private static string Id(GodotObject value) => value.Get("id").AsString();
    private static string ItemId(TreeItem? item) => item?.GetMetadata(0).AsString() ?? "";
    private static Texture2D Icon(string name) => GD.Load<Texture2D>("res://resources/Images/ActorIcons/" + name + ".svg");
    public void ready(Tree owner)
    {
        owner.SizeFlagsHorizontal = owner.SizeFlagsVertical = Control.SizeFlags.ExpandFill;
        owner.HideRoot = false; owner.AllowReselect = true; owner.SelectMode = Tree.SelectModeEnum.Multi; owner.DropModeFlags = (int)Tree.DropModeFlagsEnum.OnItem;
        owner.CustomMinimumSize = new Vector2(220, 150); apply_theme(owner);
        owner.Connect("button_clicked", new Callable(owner, "_section_button_clicked")); owner.Connect("item_edited", new Callable(owner, "_section_edited"));
    }
    public void section_button_clicked(Tree owner, TreeItem item, int column, int id, int mouseButton)
    {
        var model = Model(owner); if (mouseButton != (int)MouseButton.Left || model == null) return;
        if (item == owner.GetRoot() && id == 0) model.Call("create_section");
        else if (id is 1 or 2)
        {
            var actor = Actor(model, ItemId(item));
            if (actor != null) model.Call(id == 1 ? "set_timeline_children_visible" : "set_timeline_children_linked", Id(actor), !actor.Get(id == 1 ? "show_timeline_children" : "link_timeline_children").AsBool());
        }
    }
    public void section_edited(Tree owner)
    {
        var item = owner.GetEdited(); string id = ItemId(item);
        if (item != null && id.StartsWith("section:", StringComparison.Ordinal)) Model(owner)?.Call("rename_section", id[8..], item.GetText(0));
    }
    public void setup(Tree owner, RefCounted? model, RefCounted? registry)
    {
        Disconnect(owner); owner.Set("model", model == null ? default(Variant) : Variant.From(model)); owner.Set("registry", registry == null ? default(Variant) : Variant.From(registry));
        model?.Connect("changed", new Callable(owner, "_request_rebuild")); request_rebuild(owner);
    }
    private static void Disconnect(Tree owner)
    {
        var model = Model(owner); var callback = new Callable(owner, "_request_rebuild");
        if (model?.IsConnected("changed", callback) == true) model.Disconnect("changed", callback);
    }
    public void exit_tree(Tree owner) { Disconnect(owner); owner.Set("_rebuild_scheduled", false); Items(owner).Clear(); }
    public void request_rebuild(Tree owner)
    {
        if (owner.Get("_rebuild_scheduled").AsBool() || !owner.IsInsideTree() || owner.IsQueuedForDeletion()) return;
        owner.Set("_rebuild_scheduled", true); owner.CallDeferred("_refresh_from_model");
    }
    public void refresh_from_model(Tree owner)
    {
        owner.Set("_rebuild_scheduled", false);
        if (Model(owner) == null || !owner.IsInsideTree() || owner.IsQueuedForDeletion()) return;
        if (owner.Get("_structure_signature").AsString() == model_structure_signature(owner)) sync_selection(owner); else rebuild(owner);
    }
    public string model_structure_signature(Tree owner)
    {
        var model = Model(owner); if (model == null) return "";
        var parts = new List<string>();
        foreach (var value in model.Get("sections").AsGodotArray()) { var section = value.AsGodotObject(); parts.Add("section:" + Id(section) + "|" + section.Get("display_name").AsString()); }
        foreach (var value in Actors(model))
        {
            var actor = value.AsGodotObject();
            parts.Add(string.Join('|', new[] { "id", "parent_id", "type_id", "display_name", "section_id", "show_timeline_children", "link_timeline_children" }.Select(key => actor.Get(key).ToString())));
        }
        return string.Join('\n', parts);
    }
    public void rebuild(Tree owner)
    {
        owner.Set("_rebuild_scheduled", false); var model = Model(owner);
        if (model == null || !owner.IsInsideTree() || owner.IsQueuedForDeletion()) return;
        var collapsed = new Settings(); var items = Items(owner);
        foreach (var pair in items) if (pair.Value.As<TreeItem>() is TreeItem item && GodotObject.IsInstanceValid(item)) collapsed[pair.Key] = item.Collapsed;
        owner.Set("_rebuilding", true); owner.Clear(); items.Clear();
        var root = owner.CreateItem();
        if (root == null) { owner.Set("_rebuilding", false); return; }
        root.SetText(0, "SCENE"); root.SetMetadata(0, ""); root.SetCustomColor(0, new Color("8de0ca")); root.SetSelectable(0, false); root.AddButton(0, Icon("AddSection"), 0, false, "Create section");
        var children = new Settings { [""] = new GArray() };
        var actorIds = new HashSet<string>(Actors(model).Select(v => Id(v.AsGodotObject())));
        foreach (var value in Actors(model))
        {
            var actor = value.AsGodotObject(); string parent = actor.Get("parent_id").AsString();
            if (!actorIds.Contains(parent)) parent = "section:" + actor.Get("section_id").AsString();
            if (!children.ContainsKey(parent)) children[parent] = new GArray(); children[parent].AsGodotArray().Add(value);
        }
        foreach (var value in model.Get("sections").AsGodotArray())
        {
            var section = value.AsGodotObject(); var item = owner.CreateItem(root); string key = "section:" + Id(section);
            item.SetText(0, section.Get("display_name").AsString()); item.SetMetadata(0, key); item.SetEditable(0, true); item.SetTooltipText(0, "Select to edit this section's timeline. Drag actors here to move them. Double-click to rename."); item.SetCustomColor(0, new Color("8de0ca"));
            item.Collapsed = collapsed.TryGetValue(key, out var closed) && closed.AsBool(); items[key] = item;
            add_children(owner, item, key, children, collapsed, new Settings());
        }
        owner.Set("_structure_signature", model_structure_signature(owner)); sync_selection(owner);
        var selected = model.Call("selected_actor").As<Resource>();
        if (selected != null && items.TryGetValue(Id(selected), out var selectedItem))
        {
            owner.ScrollToItem(selectedItem.As<TreeItem>(), true);
            if (owner.Get("_selection_anchor").AsString() == "") owner.Set("_selection_anchor", Id(selected));
        }
        owner.Set("_rebuilding", false);
    }
    public void sync_selection(Tree owner)
    {
        var model = Model(owner); if (model == null || !owner.IsInsideTree()) return;
        owner.Set("_rebuilding", true); owner.DeselectAll(); string section = "section:" + model.Get("selected_section_id").AsString(); var items = Items(owner);
        foreach (var pair in items) if (pair.Key.AsString().StartsWith("section:", StringComparison.Ordinal)) pair.Value.As<TreeItem>().SetCustomBgColor(0, pair.Key.AsString() == section ? new Color("203f46") : Colors.Transparent);
        var selectedIds = model.Get("selected_ids").AsGodotArray();
        if (selectedIds.Count == 0 && items.TryGetValue(section, out var sectionItem)) sectionItem.As<TreeItem>().Select(0);
        foreach (var id in selectedIds)
        {
            int index = model.Call("_index_of", id).AsInt32();
            if (index >= 0 && items.TryGetValue(Id(Actors(model)[index].AsGodotObject()), out var item)) item.As<TreeItem>().Select(0);
        }
        owner.Set("_rebuilding", false);
    }
    public void add_children(Tree owner, TreeItem parentItem, string parentId, Settings children, Settings collapsed, Settings visited)
    {
        if (visited.ContainsKey(parentId)) return; visited[parentId] = true;
        if (!children.TryGetValue(parentId, out var values)) return;
        var branch = values.AsGodotArray().Select(v => v.As<Resource>()).ToList();
        using var compare = new Expression(); compare.Parse("a.naturalnocasecmp_to(b)", new[] { "a", "b" });
        branch.Sort((a, b) => compare.Execute(new GArray { a.Get("display_name"), b.Get("display_name") }).AsInt32());
        var model = Model(owner)!; var registry = owner.Get("registry").As<RefCounted>();
        foreach (var actor in branch)
        {
            string id = Id(actor); var item = owner.CreateItem(parentItem); item.SetText(0, actor.Get("display_name").AsString()); item.SetMetadata(0, id);
            if (children.TryGetValue(id, out var descendants) && descendants.AsGodotArray().Count > 0)
            {
                bool shown = actor.Get("show_timeline_children").AsBool(), linked = actor.Get("link_timeline_children").AsBool();
                item.AddButton(0, Icon(shown ? "TimelineChildrenShown" : "TimelineChildrenHidden"), 1, false, shown ? "Collapse children in timeline (does not hide objects in the viewport)" : "Expand children in timeline (does not change viewport visibility)");
                item.AddButton(0, Icon(linked ? "ChildrenLinked" : "ChildrenUnlinked"), 2, false, linked ? "Unlink child clip movement and trimming" : "Link child clip movement and trimming");
            }
            item.SetTooltipText(0, model.Call("actor_path", id).AsString()); item.Collapsed = collapsed.TryGetValue(id, out var closed) && closed.AsBool();
            var definition = registry?.Call("get_definition", actor.Get("type_id")).As<Resource>(); var icon = definition?.Get("icon").As<Texture2D>();
            if (icon != null) { item.SetIcon(0, icon); item.SetIconMaxWidth(0, 20); }
            Items(owner)[id] = item; add_children(owner, item, id, children, collapsed, visited.Duplicate());
        }
    }
    public void apply_theme(Tree owner)
    {
        static StyleBoxFlat Style(string background, string border, int radius)
        {
            var style = new StyleBoxFlat { BgColor = new Color(background), BorderColor = new Color(border) }; style.SetBorderWidthAll(1); style.SetCornerRadiusAll(radius); return style;
        }
        var panel = Style("131c27", "33485c", 7); panel.ContentMarginLeft = panel.ContentMarginRight = panel.ContentMarginTop = panel.ContentMarginBottom = 5; owner.AddThemeStyleboxOverride("panel", panel);
        var selected = Style("245b5b", "72cfb8", 5); owner.AddThemeStyleboxOverride("selected", selected); owner.AddThemeStyleboxOverride("selected_focus", selected);
        var hover = (StyleBoxFlat)selected.Duplicate(); hover.BgColor = new Color("263b4b"); hover.BorderColor = new Color("49677f"); owner.AddThemeStyleboxOverride("hovered", hover);
        owner.AddThemeColorOverride("font_color", new Color("cedbe7")); owner.AddThemeColorOverride("font_selected_color", Colors.White); owner.AddThemeConstantOverride("v_separation", 5); owner.AddThemeConstantOverride("h_separation", 7);
    }
}
