using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class ClipboardWindowOperations
{
    public Button make_button(Node parent, string text, string tip)
    {
        var button = new Button { Text = text, TooltipText = tip }; button.AddThemeFontSizeOverride("font_size", 12); parent.AddChild(button); return button;
    }
    private Button Button(Control owner, Node parent, string text, Action action, string tip = "")
    {
        var button = make_button(parent, text, tip); button.Pressed += () => { if (GodotObject.IsInstanceValid(owner)) action(); }; return button;
    }
    public void prompt(Control owner, string title, string value, Variant confirmed) => Prompt(owner, title, value, text => owner.Call("_invoke_window_callback", confirmed, text));
    public void build_theme(Control owner)
    {
        var theme = new Theme(); owner.Theme = theme;
        foreach (string type in new[] { "Label", "Button", "MenuButton", "LineEdit", "ItemList", "Tree", "PopupMenu" }) { theme.SetFontSize("font_size", type, 13); theme.SetColor("font_color", type, new Color("d9e9ef")); }
        foreach (string type in new[] { "Button", "MenuButton" }) foreach (string state in new[] { "normal", "hover", "pressed", "focus", "disabled" })
        {
            var box = new StyleBoxFlat { BgColor = new Color(state == "pressed" ? "214b46" : state == "hover" ? "213443" : "172734"), BorderColor = new Color(state is "pressed" or "focus" ? "70ddbd" : "344f61") }; box.SetBorderWidthAll(1); box.SetCornerRadiusAll(5); box.ContentMarginLeft = box.ContentMarginRight = 9; box.ContentMarginTop = box.ContentMarginBottom = 5; theme.SetStylebox(state, type, box);
        }
        foreach (string type in new[] { "LineEdit", "ItemList", "Tree" })
        {
            var panel = new StyleBoxFlat { BgColor = new Color("101a24"), BorderColor = new Color("2b4354") }; panel.SetBorderWidthAll(1); panel.SetCornerRadiusAll(5); panel.ContentMarginLeft = panel.ContentMarginRight = panel.ContentMarginTop = panel.ContentMarginBottom = 6; theme.SetStylebox(type == "LineEdit" ? "normal" : "panel", type, panel);
        }
    }
    public void configure(Control owner, Node host)
    {
        owner.Set("service", host); owner.Set("store", host.Get("store")); owner.Name = "SuperClipboardWindow"; owner.CustomMinimumSize = new Vector2(540, 340); owner.MouseFilter = Control.MouseFilterEnum.Stop; owner.FocusMode = Control.FocusModeEnum.All; build_theme(owner);
        var style = new StyleBoxFlat { BgColor = new Color("101b25"), BorderColor = new Color("4c9d8b") }; style.SetBorderWidthAll(2); style.SetCornerRadiusAll(10); style.ContentMarginLeft = style.ContentMarginRight = style.ContentMarginTop = style.ContentMarginBottom = 10; owner.AddThemeStyleboxOverride("panel", style);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation", 7); owner.AddChild(column); var title = new HBoxContainer(); column.AddChild(title);
        var grip = new Label { Text = "⠿  SUPER CLIPBOARD", SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, MouseFilter = Control.MouseFilterEnum.Stop }; grip.AddThemeColorOverride("font_color", new Color("88e7ca")); title.AddChild(grip); grip.Connect("gui_input", new Callable(owner, "_title_input"));
        Button(owner, title, "↶", () => Store(owner).Get("history").As<UndoRedo>().Undo(), "Undo clipboard change"); Button(owner, title, "↷", () => Store(owner).Get("history").As<UndoRedo>().Redo(), "Redo clipboard change"); Button(owner, title, "×", () => close(owner), "Close · F8 / Escape");
        var search = Field<LineEdit>(owner, "search"); search.PlaceholderText = "Search names or resource types…"; search.ClearButtonEnabled = true; column.AddChild(search); search.TextChanged += _ => { if (GodotObject.IsInstanceValid(owner)) owner.Call("_refresh_files"); };
        var toolbar = new HBoxContainer(); column.AddChild(toolbar); Button(owner, toolbar, "Save active", () => _service.save_active_document(Service(owner)), "Save an editable snapshot of the active document"); Button(owner, toolbar, "＋ Folder", () => Prompt(owner, "New folder", "", text => _store.create_folder(Store(owner), text, Folder(owner))));
        var actions = new MenuButton { Text = "Organize ▾" }; toolbar.AddChild(actions); foreach (string label in new[] { "Rename · F2", "Move to folder…", "Duplicate · Ctrl+D", "Copy · Ctrl+C", "Cut · Ctrl+X", "Paste · Ctrl+V", "Delete to Trash" }) actions.GetPopup().AddItem(label); actions.GetPopup().IdPressed += index => { if (GodotObject.IsInstanceValid(owner)) organize(owner, (int)index); };
        Button(owner, toolbar, "▦", () => { owner.Set("grid", !owner.Get("grid").AsBool()); owner.Call("_refresh_files"); }, "List / thumbnails"); Button(owner, toolbar, "Trash", () => { owner.Set("trash", !Trash(owner)); owner.Call("_refresh_files"); }, "Recover deleted resources");
        var split = new HSplitContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill }; column.AddChild(split); split.SplitOffsets = new[] { 165 };
        var tree = Field<Tree>(owner, "tree"); tree.HideRoot = false; tree.CustomMinimumSize = new Vector2(145, 0); split.AddChild(tree);
        tree.ItemSelected += () => { if (!GodotObject.IsInstanceValid(owner)) return; var item = tree.GetSelected(); if (item != null) { owner.Set("folder", item.GetMetadata(0)); owner.Set("trash", false); owner.Call("_refresh_files"); } };
        tree.SetDragForwarding(Callable.From<Vector2, Variant>(_ => folder_drag(owner)), Callable.From<Vector2, Variant, bool>((at, data) => folder_can_drop(owner, at, data)), Callable.From<Vector2, Variant>((at, data) => folder_drop(owner, at, data)));
        var right = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; split.AddChild(right); var files = Field<ItemList>(owner, "files"); files.SelectMode = ItemList.SelectModeEnum.Multi; files.SizeFlagsHorizontal = files.SizeFlagsVertical = Control.SizeFlags.ExpandFill; files.AutoHeight = false; right.AddChild(files);
        files.SetDragForwarding(Callable.From<Vector2, Variant>(_ => file_drag(owner)), Callable.From<Vector2, Variant, bool>((_, data) => can_drop(data)), Callable.From<Vector2, Variant>((_, data) => drop(owner, data)));
        files.MultiSelected += (_, _) => { if (GodotObject.IsInstanceValid(owner)) owner.Call("_preview"); }; files.ItemActivated += _ => { if (GodotObject.IsInstanceValid(owner)) use(owner); }; files.GetVScrollBar().ValueChanged += _ => { if (GodotObject.IsInstanceValid(owner)) queue_thumbnails(owner); };
        var info = new HBoxContainer(); right.AddChild(info); var preview = Field<TextureRect>(owner, "preview"); preview.CustomMinimumSize = new Vector2(76, 56); preview.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize; preview.StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered; info.AddChild(preview);
        var details = Field<Label>(owner, "details"); details.Text = "Drag files in to save; drag files out to reuse."; details.AutowrapMode = TextServer.AutowrapMode.WordSmart; details.MaxLinesVisible = 3; details.CustomMinimumSize = new Vector2(180, 0); details.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; info.AddChild(details);
        var bottom = new HBoxContainer(); column.AddChild(bottom); var defaultButton = Field<Button>(owner, "default_button"); defaultButton.Text = "★ Set default"; defaultButton.TooltipText = "Use the selected resource as the Default Slot in asset pickers"; defaultButton.Disabled = true; defaultButton.Pressed += () => { if (!GodotObject.IsInstanceValid(owner)) return; var ids = selected(owner); if (ids.Length == 1) _store.set_default(Store(owner), ids[0]); }; bottom.AddChild(defaultButton);
        Button(owner, bottom, "Use in project", () => use(owner)); Button(owner, bottom, "Restore", () => _store.delete(Store(owner), selected(owner), true)); var status = Field<Label>(owner, "status"); status.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; status.TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis; bottom.AddChild(status);
        var resize = new Button { Text = "◢" }; bottom.AddChild(resize); resize.Connect("gui_input", new Callable(owner, "_resize_input")); foreach (Control control in new Control[] { owner, files, tree, search }) control.Connect("gui_input", new Callable(owner, "_keys"));
        var state = Map(Data(owner), "ui"); owner.Set("folder", Get(state, "folder", "default")); owner.Set("grid", Get(state, "grid", false)); owner.Size = new Vector2(Get(state, "width", 760).AsSingle(), Get(state, "height", 470).AsSingle()); owner.Position = new Vector2(Get(state, "x", 80).AsSingle(), Get(state, "y", 100).AsSingle()); clamp_window(owner);
        search.Text = Get(state, "search", "").AsString(); Store(owner).Connect("changed", new Callable(owner, "_refresh")); refresh(owner); owner.CallDeferred("_restore_bounds", state); owner.GetViewport().Connect("size_changed", new Callable(owner, "_clamp_window"));
    }
}
