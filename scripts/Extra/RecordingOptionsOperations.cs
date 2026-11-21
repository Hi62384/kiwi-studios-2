using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class RecordingOptionsOperations : RefCounted
{
    private readonly ActorAudioRecorderOperations _audio = new();
    private readonly ActorScreenRecorderOperations _screen = new();
    private static Settings Preferences(Button owner) => owner.Get("preferences").AsGodotDictionary();
    private static bool Alive(Button owner) => GodotObject.IsInstanceValid(owner) && !owner.IsQueuedForDeletion();
    public void ready(Button owner) => owner.Connect("pressed", new Callable(owner, "open_settings"));
    public void screen_ready(Button owner) => owner.Connect("pressed", new Callable(owner, "_screen_pressed"));
    public void open_settings(Button owner)
    {
        owner.Set("preferences", _audio.read_preferences()); var previous = owner.Get("popup").As<PopupPanel>(); if (GodotObject.IsInstanceValid(previous)) previous!.QueueFree();
        var popup = new PopupPanel(); owner.Set("popup", popup); owner.AddChild(popup); var panel = new StyleBoxFlat { BgColor = new Color("15232b"), BorderColor = new Color("4d867c"), ContentMarginLeft = 18, ContentMarginRight = 18, ContentMarginTop = 16, ContentMarginBottom = 16 }; panel.SetBorderWidthAll(1); panel.SetCornerRadiusAll(10); popup.AddThemeStyleboxOverride("panel", panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation", 12); popup.AddChild(column); var title = new Label { Text = "Recording options" }; title.AddThemeFontSizeOverride("font_size", 20); title.AddThemeColorOverride("font_color", new Color("b4f1de")); column.AddChild(title); owner.Call("_add_capture_options", column);
        var heading = new Label { Text = "AUDIO SOURCES", Modulate = new Color("8fb5b1") }; heading.AddThemeFontSizeOverride("font_size", 11); column.AddChild(heading);
        foreach (var source in new[] { ("record_mic", "RecordMicrophone", "Record microphone audio"), ("record_system", "RecordSystemAudio", "Record system audio"), ("record_timeline", "RecordTimelineAudio", "Record timeline audio") })
        {
            var enabled = new CheckBox { Name = source.Item2, Text = source.Item3, TooltipText = source.Item1 == "record_timeline" ? "Play and capture audio actors while the recording playhead advances." : "", ButtonPressed = Preferences(owner)[source.Item1].AsBool() }; column.AddChild(enabled);
            enabled.Toggled += value => { if (!Alive(owner)) return; Preferences(owner)[source.Item1] = value; _audio.write_preferences(Preferences(owner)); };
        }
        var row = new HBoxContainer(); column.AddChild(row); var device = new OptionButton { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; owner.Set("device", device); row.AddChild(device); var refresh = new Button { Text = "↻", TooltipText = "Refresh input devices" }; row.AddChild(refresh); refresh.Connect("pressed", new Callable(owner, "_refresh_devices")); refresh_devices(owner);
        device.ItemSelected += index => { if (!Alive(owner)) return; Preferences(owner)["device"] = device.GetItemText((int)index); _audio.write_preferences(Preferences(owner)); };
        var gainRow = new HBoxContainer(); column.AddChild(gainRow); gainRow.AddChild(new Label { Text = "Input gain", SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }); var gain = new DragNumber(); gain.Name = "InputGain"; gain.MinValue = -36; gain.MaxValue = 24; gain.Step = .01; gain.Suffix = " dB"; gain.Value = Preferences(owner)["gain_db"].AsDouble(); gain.CustomMinimumSize = new Vector2(120, 0); gainRow.AddChild(gain);
        void SaveGain(double value) { if (!Alive(owner)) return; Preferences(owner)["gain_db"] = value; _audio.write_preferences(Preferences(owner)); }
        gain.ValueChanged += SaveGain; gain.Connect("preview_changed", Callable.From<double>(value => { if (Alive(owner)) Preferences(owner)["gain_db"] = value; })); gain.Connect("drag_committed", Callable.From<double>(SaveGain)); gain.Connect("drag_cancelled", Callable.From(() => { if (Alive(owner)) Preferences(owner)["gain_db"] = gain.Value; }));
        var mono = new CheckButton { Text = "Record mono", ButtonPressed = Preferences(owner)["mono"].AsBool() }; column.AddChild(mono); mono.Toggled += value => { if (!Alive(owner)) return; Preferences(owner)["mono"] = value; _audio.write_preferences(Preferences(owner)); };
        var close = new Button { Text = "Close" }; column.AddChild(close); close.Connect("pressed", new Callable(popup, "hide")); popup.Size = new Vector2I(340, 0); popup.Position = (Vector2I)(owner.GetScreenPosition() + new Vector2(0, owner.Size.Y + 5)); popup.Popup();
    }
    public void refresh_devices(Button owner)
    {
        var device = owner.Get("device").As<OptionButton>(); device.Clear(); var devices = new System.Collections.Generic.List<string>(AudioServer.GetInputDeviceList()); if (!devices.Contains("Default")) devices.Insert(0, "Default");
        foreach (string name in devices) { device.AddItem(name); if (name == Preferences(owner)["device"].AsString()) device.Select(device.ItemCount - 1); }
    }
    public void add_capture_options(Button owner, VBoxContainer column)
    {
        column.AddChild(new Label { Text = "SCREEN CAPTURE" }); var targets = _screen.targets(); var filtered = new Godot.Collections.Array<Settings>(); var tabs = new HBoxContainer(); tabs.AddThemeConstantOverride("separation", 6); column.AddChild(tabs);
        var selector = new OptionButton { Name = "CaptureTarget", CustomMinimumSize = new Vector2(300, 0), TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis }; column.AddChild(selector); var note = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart, CustomMinimumSize = new Vector2(300, 0), Modulate = new Color("8fb5b1"), Visible = false }; note.AddThemeFontSizeOverride("font_size", 11); column.AddChild(note); var group = new ButtonGroup();
        foreach (string category in new[] { "Entire display", "Windows" })
        {
            var tab = new Button { Text = category, ToggleMode = true, ButtonGroup = group, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, CustomMinimumSize = new Vector2(0, 34) }; var style = new StyleBoxFlat { BgColor = new Color("24423f"), BorderColor = new Color("78d9c4") }; style.SetBorderWidthAll(1); style.SetCornerRadiusAll(6); tab.AddThemeStyleboxOverride("pressed", style); tabs.AddChild(tab);
            tab.Pressed += () =>
            {
                selector.Clear(); filtered.Clear(); foreach (var target in targets) if ((target.TryGetValue("category", out var value) ? value.AsString() : "Entire display") == category) { filtered.Add(target); selector.AddItem(target["label"].AsString()); }
                selector.Disabled = filtered.Count == 0; if (filtered.Count == 0) selector.AddItem("No available sources"); note.Visible = category != "Entire display"; note.Text = "Keep the selected window visible and uncovered during capture.";
            };
        }
        tabs.GetChild<Button>(0).ButtonPressed = true; tabs.GetChild<Button>(0).EmitSignal("pressed"); var resolution = new OptionButton { Name = "CaptureResolution" }; resolution.AddItem("Native resolution · original pixels", 0); foreach (int height in new[] { 720, 1080, 1440, 2160 }) resolution.AddItem(height + "p · preserve aspect ratio", height); column.AddChild(resolution); var fps = new OptionButton(); foreach (int rate in new[] { 24, 30, 60 }) fps.AddItem(rate + " fps", rate); fps.Select(1); column.AddChild(fps); var cursor = new CheckBox { Text = "Include mouse pointer", ButtonPressed = true }; column.AddChild(cursor);
        var start = new Button { Text = "● Start screen recording" }; column.AddChild(start); start.Pressed += () =>
        {
            if (!Alive(owner) || filtered.Count == 0 || selector.Selected < 0 || selector.Selected >= filtered.Count) return; var options = Preferences(owner).Duplicate(); options["screen_fps"] = fps.GetSelectedId(); options["screen_resolution"] = resolution.GetSelectedId(); options["screen_cursor"] = cursor.ButtonPressed; owner.Get("popup").As<PopupPanel>().Hide(); owner.EmitSignal("recording_requested", options, filtered[selector.Selected]);
        };
    }
}
