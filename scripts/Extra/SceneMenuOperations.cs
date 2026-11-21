using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SceneMenuOperations : RefCounted
{
    private static Control? Timeline(Control owner) => owner.Get("timeline").As<Control>();
    private static TabBar? Tabs(Control owner) => owner.Get("scene_tabs").As<TabBar>();
    public void ready(Button owner)
    {
        var timeline = owner.GetNodeOrNull<Control>("../../HSplitContainer/VSplitContainer2/ActorTimeline"); var tabs = owner.GetNodeOrNull<TabBar>("../../../../../Tabs"); owner.Set("timeline", timeline == null ? default(Variant) : Variant.From(timeline)); owner.Set("scene_tabs", tabs == null ? default(Variant) : Variant.From(tabs)); owner.Connect("pressed", new Callable(owner, "_open_menu")); owner.TooltipText = "Save or load an editable scene";
    }
    public void unhandled_key_input(Control owner, InputEvent input)
    {
        if (input is not InputEventKey { Pressed: true, Echo: false, CtrlPressed: true } key) return;
        if (key.Keycode == Key.S) owner.Call(key.ShiftPressed ? "_save_as" : "_save"); else if (key.Keycode == Key.O) owner.Call("_load"); else return; owner.GetViewport().SetInputAsHandled();
    }
    public StyleBoxFlat box(Color color, Color border, int radius, int width)
    {
        var style = new StyleBoxFlat { BgColor = color, BorderColor = border }; style.SetBorderWidthAll(width); style.SetCornerRadiusAll(radius); return style;
    }
    public string relative_path(string path)
    {
        string root = GD.Load<GDScript>("res://scripts/actors/core/actor_project_file_picker.gd").Call("root_directory").AsString().Replace('\\', '/').TrimEnd('/'), normalized = path.Replace('\\', '/'); string prefix = root + "/"; return "Project / " + (normalized.StartsWith(prefix, StringComparison.Ordinal) ? normalized[prefix.Length..] : normalized);
    }
    public string active_path(Control owner) => Tabs(owner)?.Call("current_scene_path").AsString() ?? owner.Get("current_scene_path").AsString();
    private void AddAction(Control owner, VBoxContainer parent, string title, string shortcut, string subtitle, Action action)
    {
        var button = new Button { CustomMinimumSize = new Vector2(0, 52), Alignment = HorizontalAlignment.Left, Text = "  " + title + "\n  " + subtitle, TooltipText = shortcut }; button.AddThemeFontSizeOverride("font_size", 13); button.AddThemeColorOverride("font_color", new Color("edf6ff")); button.AddThemeColorOverride("font_hover_color", Colors.White); button.AddThemeStyleboxOverride("normal", box(new Color("182532"), new Color("263a4a"), 7, 1)); button.AddThemeStyleboxOverride("hover", box(new Color("254052"), new Color("65d8bd"), 7, 1));
        button.Pressed += () => { if (!GodotObject.IsInstanceValid(owner)) return; var menu = owner.Get("menu").As<PopupPanel>(); if (GodotObject.IsInstanceValid(menu)) menu!.Hide(); action(); }; parent.AddChild(button);
    }
    public void add_action(Control owner, VBoxContainer parent, string title, string shortcut, string subtitle, Variant action) => AddAction(owner, parent, title, shortcut, subtitle, () => owner.Call("_invoke_scene_action", action));
    public void open_menu(Control owner)
    {
        var previous = owner.Get("menu").As<PopupPanel>(); if (GodotObject.IsInstanceValid(previous)) previous!.QueueFree(); var menu = new PopupPanel(); owner.Set("menu", menu); owner.AddChild(menu); menu.AddThemeStyleboxOverride("panel", box(new Color("101a25"), new Color("4b6a80"), 12, 2)); var margin = new MarginContainer(); foreach (string side in new[] { "left", "right", "top", "bottom" }) margin.AddThemeConstantOverride("margin_" + side, 14); menu.AddChild(margin); var column = new VBoxContainer { CustomMinimumSize = new Vector2(330, 0) }; column.AddThemeConstantOverride("separation", 7); margin.AddChild(column);
        var eyebrow = new Label { Text = "EDITABLE SCENE" }; eyebrow.AddThemeFontSizeOverride("font_size", 10); eyebrow.AddThemeColorOverride("font_color", new Color("6fdcc1")); column.AddChild(eyebrow); var title = new Label { Text = "Scene file" }; title.AddThemeFontSizeOverride("font_size", 20); title.AddThemeColorOverride("font_color", new Color("eff7ff")); column.AddChild(title);
        string path = active_path(owner); var label = new Label { Text = path == "" ? "Not saved yet" : relative_path(path), ClipText = true, TooltipText = path }; label.AddThemeColorOverride("font_color", new Color("8da7ba")); owner.Set("path_label", label); column.AddChild(label); column.AddChild(new HSeparator());
        AddAction(owner, column, "Save Scene", "Ctrl+S", "Save every actor and editor state", () => owner.Call("_save")); AddAction(owner, column, "Save Scene As…", "Ctrl+Shift+S", "Choose a new project location", () => owner.Call("_save_as"));
        AddAction(owner, column, "Save to Super Clipboard", "F8 opens library", "Store an independent editable scene", () =>
        {
            var timeline = Timeline(owner); var value = GD.Load<GDScript>("res://scripts/clipboard/super_clipboard_service.gd").Get("instance"); if (timeline != null && value.VariantType == Variant.Type.Object && value.AsGodotObject() is Node service && GodotObject.IsInstanceValid(service)) new SuperClipboardOperations().quick_save(service, timeline.Call("capture_scene_data"), Tabs(owner)?.Call("current_scene_name").AsString() ?? "Scene", "default");
        });
        AddAction(owner, column, "Load Scene…", "Ctrl+O", "Open a .tres editable scene", () => owner.Call("_load")); AddAction(owner, column, "Instantiate Scene…", "", "Add another scene under a linked 3D point", () => owner.Call("_instantiate_scene")); menu.PopupHide += menu.QueueFree; menu.Position = (Vector2I)(owner.GlobalPosition + new Vector2(0, owner.Size.Y + 4)); menu.Popup();
    }
    public string suggested_name(Control owner)
    {
        string path = active_path(owner); return path != "" ? path.GetFile().GetBaseName() : Tabs(owner)?.Call("current_scene_name").AsString() ?? "New Scene";
    }
    public Resource? capture_scene(Control owner) => Timeline(owner)?.Call("capture_scene_data").As<Resource>();
    public void write_scene(Control owner, string path)
    {
        var tabs = Tabs(owner); if (tabs != null) { int result = tabs.Call("save_current", path).AsInt32(); if (result != (int)Error.Ok) GD.PushError($"Could not save actor scene '{path}' (error {result})."); return; }
        var scene = capture_scene(owner); if (scene == null) return; scene.ResourceName = path.GetFile().GetBaseName(); var error = ResourceSaver.Save(scene, path);
        if (error != Error.Ok) { GD.PushError($"Could not save actor scene '{path}' (error {(int)error})."); return; }
        owner.Set("current_scene_path", path); var files = GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd"); if (files.Get("node").VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(files.Get("node").AsGodotObject())) new LocalProjectFilesystemOperations().update_root_folder();
    }
    public Resource picker_property()
    {
        var property = new ActorProperty(); property.Set("options", new Settings { ["extensions"] = new[] { "tres" }, ["native_resource_types"] = new[] { "ActorSceneData" } }); return property;
    }
    public void load_scene(Control owner, string path)
    {
        if (path is "" or "::empty-resource::") return; var scene = ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore);
        if (!ActorDataOperations.ScriptIs(scene, "res://scripts/actors/core/actor_scene_data.gd")) { GD.PushError("The chosen file is not an editable actor scene: " + path); return; }
        var tabs = Tabs(owner); if (tabs != null) tabs.Call("open_scene", path); else { owner.Set("current_scene_path", path); Timeline(owner)?.Call("restore_scene_data", scene); }
    }
    public void instantiate_scene(Control owner, string path)
    {
        if (path is "" or "::empty-resource::") return; var timeline = Timeline(owner); if (timeline == null) return;
        var source = ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore); if (!ActorDataOperations.ScriptIs(source, "res://scripts/actors/core/actor_scene_data.gd")) return;
        var model = timeline.Get("model").As<RefCounted>(); model.Call("instantiate_scene", source, timeline.Get("registry").As<RefCounted>().Call("get_definition", new StringName("point_3d")), timeline.Get("canvas").As<Control>().Get("playhead"), model.Get("selected_layer"), path.GetFile().GetBaseName());
    }
}
