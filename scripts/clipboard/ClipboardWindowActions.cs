using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ClipboardWindowOperations
{
    public void use(Control owner)
    {
        var ids = selected(owner); if (ids.Length != 1) { _service.notify(Service(owner), "Select one resource to open. Drag multiple files to compatible targets.", true); return; }
        string path = _service.import_item(Service(owner), ids[0]); if (path == "") return; owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("_filesystem_resource_opened", path);
    }
    private void Prompt(Control owner, string title, string value, Action<string> confirmed)
    {
        var popup = new ConfirmationDialog { Title = title }; owner.AddChild(popup); var input = new LineEdit { Text = value }; popup.AddChild(input);
        popup.Confirmed += () => { if (GodotObject.IsInstanceValid(owner)) confirmed(input.Text); popup.QueueFree(); }; popup.Canceled += popup.QueueFree; popup.PopupCentered(new Vector2I(310, 100)); input.GrabFocus(); input.SelectAll();
    }
    public void rename(Control owner)
    {
        var ids = selected(owner); string id = ids.Length == 1 ? ids[0] : Folder(owner); var data = Data(owner); var entry = Get(Map(data, "entries"), id, Get(Map(data, "folders"), id, new Settings())).AsGodotDictionary(); Prompt(owner, "Rename", Get(entry, "name", "").AsString(), text => result(owner, _store.rename(Store(owner), id, text)));
    }
    public void delete(Control owner)
    {
        var ids = selected(owner); if (ids.Length == 0 && Folder(owner) != "default") ids = new[] { Folder(owner) }; _store.delete(Store(owner), ids, false); Field<Label>(owner, "status").Text = "Moved to Trash · undo or restore to recover";
    }
    public void move_menu(Control owner)
    {
        var popup = new PopupMenu(); owner.AddChild(popup); var ids = selected(owner); if (ids.Length == 0) ids = new[] { Folder(owner) };
        foreach (var pair in Map(Data(owner), "folders")) if (_store.folder_valid(Store(owner), pair.Key.AsString())) { popup.AddItem(pair.Value.AsGodotDictionary()["name"].AsString()); popup.SetItemMetadata(popup.ItemCount - 1, pair.Key); }
        popup.IndexPressed += index => { if (GodotObject.IsInstanceValid(owner)) result(owner, _store.move(Store(owner), ids, popup.GetItemMetadata((int)index).AsString(), false)); }; popup.PopupHide += popup.QueueFree; popup.Position = (Vector2I)owner.GetGlobalMousePosition(); popup.Popup();
    }
    public Variant file_drag(Control owner)
    {
        var ids = selected(owner); var data = _service.drag_payload(Service(owner), ids); if (data.Count == 0 || ids.Length == 0) return default;
        var label = new Label { Text = Map(Map(Data(owner), "entries"), ids[0])["name"].AsString() + (ids.Length > 1 ? " +" + (ids.Length - 1) : "") }; Field<ItemList>(owner, "files").SetDragPreview(label); return data;
    }
    public Variant folder_drag(Control owner) => Folder(owner) is "" or "default" ? default(Variant) : Variant.From(new Settings { ["type"] = "clipboard_folders", ["clipboard_ids"] = new[] { Folder(owner) } });
    public bool can_drop(Variant data) => data.VariantType == Variant.Type.Dictionary && (data.AsGodotDictionary().ContainsKey("clipboard_ids") || data.AsGodotDictionary().ContainsKey("paths"));
    public bool folder_can_drop(Control owner, Vector2 at, Variant data) => Field<Tree>(owner, "tree").GetItemAtPosition(at) != null && can_drop(data);
    public void drop(Control owner, Variant data) { if (data.VariantType == Variant.Type.Dictionary) receive(owner, data.AsGodotDictionary(), Folder(owner)); }
    public void folder_drop(Control owner, Vector2 at, Variant data)
    {
        var item = Field<Tree>(owner, "tree").GetItemAtPosition(at); if (item != null && data.VariantType == Variant.Type.Dictionary) receive(owner, data.AsGodotDictionary(), item.GetMetadata(0).AsString());
    }
    private static string[] Strings(Variant value) => value.VariantType == Variant.Type.PackedStringArray ? value.AsStringArray() : value.VariantType == Variant.Type.Array ? value.AsGodotArray().Select(v => v.AsString()).ToArray() : Array.Empty<string>();
    public void receive(Control owner, Settings data, string destination)
    {
        if (destination == "") destination = "default";
        if (data.TryGetValue("clipboard_ids", out var ids)) { result(owner, _store.move(Store(owner), Strings(ids), destination, Input.IsKeyPressed(Key.Ctrl))); return; }
        foreach (string path in Strings(Get(data, "paths"))) _service.quick_save(Service(owner), path, path.GetFile().GetBaseName(), destination);
    }
    public void result(Control owner, bool ok)
    {
        if (ok) return; string error = Store(owner).Get("error").AsString(); Field<Label>(owner, "status").Text = error; _service.notify(Service(owner), error, true);
    }
    public void keys(Control owner, InputEvent input)
    {
        if (!owner.Visible || input is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.Escape) { close(owner); owner.AcceptEvent(); return; }
        if (owner.GetViewport().GuiGetFocusOwner() is LineEdit or TextEdit) return;
        var history = Store(owner).Get("history").As<UndoRedo>();
        if (key.CtrlPressed && key.Keycode == Key.Z) { if (key.ShiftPressed) history.Redo(); else history.Undo(); }
        else if (key.CtrlPressed && key.Keycode == Key.Y) history.Redo();
        else if (key.CtrlPressed && key.Keycode == Key.D) _store.move(Store(owner), selection(owner), Folder(owner), true);
        else if (key.CtrlPressed && key.Keycode is Key.C or Key.X) { owner.Set("copied", selection(owner)); owner.Set("cut", key.Keycode == Key.X); }
        else if (key.CtrlPressed && key.Keycode == Key.V) { _store.move(Store(owner), owner.Get("copied").AsStringArray(), Folder(owner), !owner.Get("cut").AsBool()); if (owner.Get("cut").AsBool()) owner.Set("copied", Array.Empty<string>()); }
        else if (key.Keycode == Key.F2) rename(owner);
        else if (key.Keycode is Key.Delete or Key.Backspace) delete(owner);
        else return;
        owner.AcceptEvent();
    }
    public void title_input(Control owner, InputEvent input)
    {
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left } mouse) { owner.Set("_dragging", mouse.Pressed); owner.Set("_origin", owner.GetGlobalMousePosition()); owner.Set("_before", owner.Position); }
        if (input is InputEventMouseMotion && owner.Get("_dragging").AsBool()) { owner.Position = owner.Get("_before").AsVector2() + owner.GetGlobalMousePosition() - owner.Get("_origin").AsVector2(); clamp_window(owner); }
        if (!owner.Get("_dragging").AsBool()) remember(owner);
    }
    public void resize_input(Control owner, InputEvent input)
    {
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left } mouse) { owner.Set("_resizing", mouse.Pressed); owner.Set("_origin", owner.GetGlobalMousePosition()); owner.Set("_before", owner.Size); }
        if (input is InputEventMouseMotion && owner.Get("_resizing").AsBool()) { owner.Size = (owner.Get("_before").AsVector2() + owner.GetGlobalMousePosition() - owner.Get("_origin").AsVector2()).Max(owner.CustomMinimumSize); clamp_window(owner); }
        if (!owner.Get("_resizing").AsBool()) remember(owner);
    }
    public void clamp_window(Control owner) { var bounds = owner.GetViewportRect().Size; owner.Size = owner.Size.Min(bounds); owner.Position = owner.Position.Clamp(Vector2.Zero, (bounds - owner.Size).Max(Vector2.Zero)); }
    public void restore_bounds(Control owner, Settings state) { owner.Size = new Vector2(Get(state, "width", 760).AsSingle(), Get(state, "height", 470).AsSingle()); clamp_window(owner); }
    public void remember(Control owner) { if (Store(owner) != null) _store.save_ui(Store(owner), new Settings { ["x"] = owner.Position.X, ["y"] = owner.Position.Y, ["width"] = owner.Size.X, ["height"] = owner.Size.Y, ["folder"] = Folder(owner), ["grid"] = owner.Get("grid"), ["search"] = Field<LineEdit>(owner, "search").Text }); }
    public void close(Control owner) { remember(owner); owner.Hide(); }
    public void organize(Control owner, int index)
    {
        switch (index)
        {
            case 0: rename(owner); break; case 1: move_menu(owner); break; case 2: _store.move(Store(owner), selection(owner), Folder(owner), true); break;
            case 3: case 4: owner.Set("copied", selection(owner)); owner.Set("cut", index == 4); break;
            case 5: _store.move(Store(owner), owner.Get("copied").AsStringArray(), Folder(owner), !owner.Get("cut").AsBool()); break; case 6: delete(owner); break;
        }
    }
}
