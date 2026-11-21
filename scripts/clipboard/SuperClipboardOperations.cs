using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SuperClipboardOperations : RefCounted
{
    private readonly ClipboardStoreOperations _store = new();
    private static RefCounted Store(Node owner) => owner.Get("store").As<RefCounted>();
    private static GDScript Bridge => GD.Load<GDScript>("res://scripts/clipboard/super_clipboard_service.gd");
    private static bool HasProject { get { var project=Variant.From(StaticData.get_loaded_project()); return project.VariantType==Variant.Type.Object && GodotObject.IsInstanceValid(project.AsGodotObject()); } }
    public void ready(Node owner)
    {
        Bridge.Set("instance", owner); var store = GD.Load<GDScript>("res://scripts/clipboard/clipboard_store.gd").New().As<RefCounted>(); owner.Set("store", store);
        if (!InputMap.HasAction("super_clipboard")) { InputMap.AddAction("super_clipboard"); InputMap.ActionAddEvent("super_clipboard", new InputEventKey { PhysicalKeycode = Key.F8 }); }
        var layer = new CanvasLayer { Layer = 1200 }; owner.Set("layer", layer); owner.AddChild(layer);
        var panel = owner.Get("toast_panel").As<PanelContainer>(); panel.MouseFilter = Control.MouseFilterEnum.Ignore; layer.AddChild(panel);
        var style = new StyleBoxFlat { BgColor = new Color("152b31"), BorderColor = new Color("427b71") }; style.SetBorderWidthAll(1); style.SetCornerRadiusAll(6); style.ContentMarginLeft = style.ContentMarginRight = style.ContentMarginTop = style.ContentMarginBottom = 8; panel.AddThemeStyleboxOverride("panel", style);
        var toast = new Label { Name = "ClipboardNotification", MouseFilter = Control.MouseFilterEnum.Ignore }; toast.AddThemeFontSizeOverride("font_size", 12); panel.AddChild(toast); panel.Hide(); owner.Set("toast", toast);
        var timer = owner.Get("toast_timer").As<Timer>(); timer.OneShot = true; owner.AddChild(timer); timer.Connect("timeout", new Callable(panel, "hide"));
        if (store.Get("error").AsString() != "") notify(owner, store.Get("error").AsString(), true);
    }
    public void input(Node owner, InputEvent input)
    {
        if (input.IsActionPressed("super_clipboard") && !input.IsEcho()) { toggle(owner); owner.GetViewport().SetInputAsHandled(); }
    }
    public void toggle(Node owner)
    {
        var window = owner.Get("window").As<Control>();
        if (!GodotObject.IsInstanceValid(window)) { window = GD.Load<GDScript>("res://scripts/clipboard/clipboard_window.gd").New().As<Control>(); owner.Set("window", window); owner.Get("layer").As<CanvasLayer>().AddChild(window); window.Call("configure", owner); }
        else if (window!.Visible) window.Call("_close"); else window.Show();
        if (window!.Visible) { window.MoveToFront(); window.Get("search").As<LineEdit>().GrabFocus(); }
    }
    public void notify(Node owner, string message, bool failed)
    {
        var toast = owner.Get("toast").As<Label>(); toast.Text = message; toast.AddThemeColorOverride("font_color", new Color(failed ? "ffab99" : "8ce8ce"));
        var panel = owner.Get("toast_panel").As<PanelContainer>(); panel.Position = new Vector2(20, owner.GetViewport().GetVisibleRect().Size.Y - 44); panel.Show(); panel.MoveToFront(); owner.Get("toast_timer").As<Timer>().Start(5);
    }
    public string quick_save(Node owner, Variant value, string title, string folder)
    {
        string id = _store.save(Store(owner), value, title, folder); notify(owner, id != "" ? "Saved to Super Clipboard · " + title : Store(owner).Get("error").AsString(), id == ""); return id;
    }
    public string import_item(Node owner, string id)
    {
        var store = Store(owner);
        if (!HasProject) { store.Set("error", "Open a project to use a clipboard resource."); notify(owner, store.Get("error").AsString(), true); return ""; }
        string root = GD.Load<GDScript>("res://scripts/actors/core/actor_project_file_picker.gd").Call("root_directory").AsString();
        string path = _store.materialize(store, id, root); if (path == "") notify(owner, store.Get("error").AsString(), true); return path;
    }
    public Settings drag_payload(Node owner, string[] ids)
    {
        if (!HasProject) return ids.Length > 0 ? new Settings { ["type"] = "super_clipboard", ["clipboard_ids"] = ids } : new Settings();
        var paths = new System.Collections.Generic.List<string>();
        foreach (string id in ids) { string path = import_item(owner, id); if (path == "") return new Settings(); paths.Add(path); }
        return paths.Count > 0 ? new Settings { ["type"] = "project_files", ["source"] = "super_clipboard", ["clipboard_ids"] = ids, ["paths"] = paths.ToArray(), ["path"] = paths[0] } : new Settings();
    }
    public void save_active_document(Node owner)
    {
        var tabs = owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs"); int index = tabs?.Get("_active_index").AsInt32() ?? -1;
        if (tabs == null || index < 0 || index >= tabs.Get("documents").AsGodotArray().Count) { notify(owner, "Open a document first.", true); return; }
        var document = tabs.Get("documents").AsGodotArray()[index].AsGodotDictionary(); Variant value;
        string kind = document.TryGetValue("type", out var type) ? type.AsString() : "scene";
        switch (kind)
        {
            case "image": { var workspace = tabs.Get("image_workspace").As<Control>(); workspace.Call("_finish_pending"); value = workspace.Get("document").AsGodotObject().Call("snapshot"); break; }
            case "model": { var workspace = tabs.Get("model_workspace").As<Control>(); workspace.Get("canvas").AsGodotObject().Call("finish_transform"); value = workspace.Get("session").AsGodotObject().Get("document").AsGodotObject().Call("snapshot"); break; }
            case "transformation": { var workspace = tabs.Get("transformation_workspace").As<Control>(); workspace.Call("finish_pending"); value = workspace.Get("session").AsGodotObject().Get("document").AsGodotObject().Call("snapshot"); break; }
            case "audio": { var workspace = tabs.Get("audio_workspace").As<Control>(); workspace.Call("capture_state"); value = workspace.Get("session").AsGodotObject().Get("document").AsGodotObject().Call("snapshot"); break; }
            case "shader": value = new Shader { Code = tabs.Get("shader_workspace").AsGodotObject().Get("editor").AsGodotObject().Get("code").As<CodeEdit>().Text }; break;
            default: value = tabs.Get("timeline").AsGodotObject().Call("capture_scene_data"); break;
        }
        quick_save(owner, value, document.TryGetValue("name", out var name) ? name.AsString() : "Document", "default");
    }
    public void exit_tree(Node owner)
    {
        var store = owner.Get("store").As<RefCounted>(); if (store != null) _store.close(store);
        if (Bridge.Get("instance").AsGodotObject() == owner) Bridge.Set("instance", default);
    }
}
