using Godot;

public partial class SceneExportButtonOperations
{
    public void open(Control owner)
    {
        var timeline = Timeline(owner); if (owner.Get("busy").AsBool() || timeline == null) return;
        var tabs = owner.GetNodeOrNull<TabBar>("../../../../../Tabs");
        if (tabs != null && tabs.CurrentTab != owner.Get("_destination_tab").AsInt32()) { owner.Set("destination", ""); owner.Set("destination_kind", ""); owner.Set("_destination_tab", tabs.CurrentTab); }
        close(owner);
        var layer = new CanvasLayer { Layer = 100 }; owner.Set("overlay_layer", layer); owner.GetTree().Root.AddChild(layer);
        var backdrop = new ColorRect { Color = new Color(.025f, .06f, .09f, .68f), MouseFilter = Control.MouseFilterEnum.Stop }; backdrop.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); layer.AddChild(backdrop);
        var center = new CenterContainer { MouseFilter = Control.MouseFilterEnum.Ignore }; center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); layer.AddChild(center);
        var panel = new PanelContainer { CustomMinimumSize = new Vector2(500, 0), MouseFilter = Control.MouseFilterEnum.Stop }; owner.Set("panel", panel); center.AddChild(panel);
        panel.AddThemeStyleboxOverride("panel", style(new Color("111b27"), new Color("527183"), 14));
        var margin = new MarginContainer(); foreach (string side in new[] { "left", "right", "top", "bottom" }) margin.AddThemeConstantOverride("margin_" + side, 18); panel.AddChild(margin);
        var column = new VBoxContainer { CustomMinimumSize = new Vector2(460, 0) }; column.AddThemeConstantOverride("separation", 12); margin.AddChild(column);
        var top = new HBoxContainer(); column.AddChild(top);
        var kicker = new Label { Text = "VIDEO EXPORT", SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; kicker.AddThemeColorOverride("font_color", new Color("6cddc4")); kicker.AddThemeFontSizeOverride("font_size", 11); top.AddChild(kicker);
        var closeButton = new Button { Text = "×", TooltipText = "Close export settings", CustomMinimumSize = new Vector2(30, 30) }; closeButton.Connect("pressed", new Callable(owner, "_close")); top.AddChild(closeButton);
        var title = new Label { Text = "Render this scene" }; title.AddThemeFontSizeOverride("font_size", 22); column.AddChild(title);
        var description = new Label { Text = "The viewport is rendered frame by frame, beginning at 0 s." }; description.AddThemeColorOverride("font_color", new Color("a5bac8")); column.AddChild(description);
        var duration = new SpinBox { MinValue = .01, MaxValue = 86400, Step = .01, Suffix = " s", Value = timeline.Get("video_duration").AsDouble(), TooltipText = "Automatically follows the rightmost actor unless changed", SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        owner.Set("duration_input", duration); duration.Connect("value_changed", new Callable(timeline, "set_video_duration"));
        var durationRow = new HBoxContainer(); durationRow.AddThemeConstantOverride("separation", 10); column.AddChild(durationRow); durationRow.AddChild(new Label { Text = "Video duration", CustomMinimumSize = new Vector2(150, 0) }); durationRow.AddChild(duration);
        var reset = button("↻", false); reset.CustomMinimumSize = new Vector2(38, 35); reset.SizeFlagsHorizontal = Control.SizeFlags.ShrinkEnd; reset.TooltipText = "Use the rightmost actor's end time again"; reset.Connect("pressed", new Callable(timeline, "reset_video_duration")); owner.Set("duration_reset", reset); durationRow.AddChild(reset); sync_duration_ui(owner);
        var resolution = new OptionButton(); foreach (string label in new[] { "HD · 1280 × 720", "Full HD · 1920 × 1080", "4K · 3840 × 2160" }) resolution.AddItem(label); resolution.Select(1); owner.Set("resolution_input", resolution); field(column, "Resolution", resolution, "");
        var fps = new OptionButton(); foreach (int rate in new[] { 24, 30, 60 }) fps.AddItem(rate + " fps", rate); fps.Select(1); owner.Set("fps_input", fps); field(column, "Frame rate", fps, "");
        var motion = new OptionButton { TooltipText = "Average deterministic subframes for motion blur, including deforming growth. Higher settings take longer." }; motion.AddItem("Motion blur off", 1); foreach (int samples in new[] { 2, 4, 8 }) motion.AddItem("Temporal blur · " + samples + " samples", samples); owner.Set("motion_input", motion); field(column, "Motion blur", motion, "");
        var aa = new OptionButton(); foreach (string label in new[] { "Use viewport setting", "2× MSAA", "4× MSAA", "8× MSAA" }) aa.AddItem(label); owner.Set("aa_input", aa); field(column, "Edge smoothing", aa, "");
        var pathHeader = new Label { Text = "SAVE VIDEO TO" }; pathHeader.AddThemeColorOverride("font_color", new Color("8da9ba")); pathHeader.AddThemeFontSizeOverride("font_size", 11); column.AddChild(pathHeader);
        var paths = new HBoxContainer(); paths.AddThemeConstantOverride("separation", 8); column.AddChild(paths);
        var project = button("Project files", false); project.Connect("pressed", new Callable(owner, "_choose_project")); owner.Set("project_button", project); paths.AddChild(project);
        var computer = button("Anywhere…", false); computer.Connect("pressed", new Callable(owner, "_choose_external")); owner.Set("computer_button", computer); paths.AddChild(computer); update_destination_buttons(owner);
        var destination = new Label { Text = "No location selected", AutowrapMode = TextServer.AutowrapMode.WordSmart, CustomMinimumSize = new Vector2(0, 44) }; destination.AddThemeColorOverride("font_color", new Color("afc5d1")); owner.Set("destination_label", destination); column.AddChild(destination);
        var status = new Label(); status.AddThemeColorOverride("font_color", new Color("72dec7")); owner.Set("status_label", status); column.AddChild(status); set_destination(owner, owner.Get("destination").AsString(), "");
        var export = button("Export MP4", true); export.CustomMinimumSize = new Vector2(0, 42); export.Connect("pressed", new Callable(owner, "_export")); owner.Set("export_button", export); column.AddChild(export);
    }
}
