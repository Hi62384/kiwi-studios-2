using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SceneExportButtonOperations : RefCounted
{
    private static T? Field<T>(Control owner, string name) where T : GodotObject
    {
        var value = owner.Get(name);
        return value.VariantType == Variant.Type.Object ? value.AsGodotObject() as T : null;
    }
    private static Control? Timeline(Control owner) => Field<Control>(owner, "timeline");
    public void ready(Button owner)
    {
        var timeline = owner.GetNodeOrNull<Control>("../../HSplitContainer/VSplitContainer2/ActorTimeline");
        owner.Set("timeline", timeline == null ? default(Variant) : Variant.From(timeline));
        owner.Connect("pressed", new Callable(owner, "_open"));
        timeline?.Get("model").As<RefCounted>().Connect("changed", new Callable(owner, "_sync_duration_ui"));
        owner.TooltipText = "Render the scene from 0 seconds to its video duration";
    }
    public void close(Control owner)
    {
        var layer = Field<CanvasLayer>(owner, "overlay_layer"); if (GodotObject.IsInstanceValid(layer)) layer!.QueueFree();
        owner.Set("overlay_layer", default); owner.Set("panel", default);
    }
    public StyleBoxFlat style(Color background, Color border, int radius)
    {
        var result = new StyleBoxFlat { BgColor = background, BorderColor = border }; result.SetBorderWidthAll(1); result.SetCornerRadiusAll(radius); return result;
    }
    public Button button(string text, bool accent)
    {
        var result = new Button { Text = text, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, CustomMinimumSize = new Vector2(0, 35) };
        result.AddThemeStyleboxOverride("normal", style(new Color(accent ? "20544e" : "223346"), new Color(accent ? "68ddc5" : "456174"), 8));
        result.AddThemeStyleboxOverride("hover", style(new Color(accent ? "327468" : "34516a"), new Color("9af1db"), 8)); return result;
    }
    public void field(VBoxContainer parent, string text, Control control, string hint)
    {
        var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 10); parent.AddChild(row);
        row.AddChild(new Label { Text = text, CustomMinimumSize = new Vector2(150, 0) });
        control.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; row.AddChild(control); if (hint != "") control.TooltipText = hint;
    }
    public void style_destination_button(Button? control, string label, bool selected)
    {
        if (!GodotObject.IsInstanceValid(control)) return;
        control!.Text = (selected ? "✓  " : "") + label;
        control.AddThemeStyleboxOverride("normal", style(new Color(selected ? "20544e" : "223346"), new Color(selected ? "68ddc5" : "456174"), 8));
        control.AddThemeStyleboxOverride("hover", style(new Color(selected ? "327468" : "34516a"), new Color("9af1db"), 8));
        control.AddThemeColorOverride("font_color", new Color(selected ? "d6fff5" : "dce9f2"));
    }
    public void update_destination_buttons(Control owner)
    {
        string kind = owner.Get("destination_kind").AsString();
        style_destination_button(Field<Button>(owner, "project_button"), "Project files", kind == "project");
        style_destination_button(Field<Button>(owner, "computer_button"), "Anywhere…", kind == "anywhere");
    }
    public void set_destination(Control owner, string path, string kind)
    {
        owner.Set("destination", path);
        if (path == "") owner.Set("destination_kind", ""); else if (kind != "") owner.Set("destination_kind", kind);
        update_destination_buttons(owner);
        var label = Field<Label>(owner, "destination_label"); if (!GodotObject.IsInstanceValid(label)) return;
        label!.Text = path == "" ? "No location selected" : "✓  " + path.GetFile() + "\n" + path.GetBaseDir(); label.TooltipText = path;
        var status = Field<Label>(owner, "status_label"); if (GodotObject.IsInstanceValid(status)) status!.Text = path == "" ? "" : "Ready to export to the selected location.";
    }
    public void sync_duration_ui(Control owner)
    {
        var timeline = Timeline(owner); if (!GodotObject.IsInstanceValid(timeline)) return;
        var input = Field<SpinBox>(owner, "duration_input"); if (GodotObject.IsInstanceValid(input)) input!.SetValueNoSignal(timeline!.Get("video_duration").AsDouble());
        var reset = Field<Button>(owner, "duration_reset"); if (GodotObject.IsInstanceValid(reset)) reset!.Visible = timeline!.Call("video_duration_is_custom").AsBool();
    }
    public string suggested_name(Control owner) => owner.GetNodeOrNull("../../../../../Tabs")?.Call("current_scene_name").AsString() ?? "Scene";
    public void choose_external(Control owner)
    {
        var picker = new FileDialog { Access = FileDialog.AccessEnum.Filesystem, FileMode = FileDialog.FileModeEnum.SaveFile, UseNativeDialog = true, Title = "Export video" };
        picker.AddFilter("*.mp4", "MP4 video"); owner.AddChild(picker);
        picker.FileSelected += path => { if (GodotObject.IsInstanceValid(owner)) set_destination(owner, path, "anywhere"); picker.QueueFree(); };
        picker.Canceled += picker.QueueFree; picker.PopupCentered(new Vector2I(900, 600));
    }
    public void request_export(Control owner)
    {
        if (owner.Get("busy").AsBool()) return;
        string destination = owner.Get("destination").AsString();
        if (destination == "") { Field<Label>(owner, "status_label")!.Text = "Choose a save location first."; return; }
        if (!FileAccess.FileExists(destination)) { owner.Call("_render_to_destination"); return; }
        var confirm = new ConfirmationDialog { Title = "Replace exported video?", DialogText = "This will replace " + destination.GetFile() + "." };
        owner.AddChild(confirm);
        confirm.Confirmed += () => { confirm.QueueFree(); if (GodotObject.IsInstanceValid(owner)) owner.Call("_render_to_destination"); };
        confirm.Canceled += confirm.QueueFree; confirm.PopupCentered();
    }
    public Settings prepare_render(Control owner)
    {
        owner.Set("busy", true); Field<Button>(owner, "export_button")!.Disabled = true;
        var dimensions = new[] { new Vector2I(1280, 720), new Vector2I(1920, 1080), new Vector2I(3840, 2160) }; var size = dimensions[Field<OptionButton>(owner, "resolution_input")!.Selected];
        var options = new Settings { ["motion_samples"] = Field<OptionButton>(owner, "motion_input")!.GetSelectedId(), ["shutter"] = .5 };
        int aa = Field<OptionButton>(owner, "aa_input")!.Selected; if (aa > 0) options["msaa"] = aa;
        return new Settings { ["width"] = size.X, ["height"] = size.Y, ["fps"] = Field<OptionButton>(owner, "fps_input")!.GetSelectedId(), ["options"] = options, ["destination"] = owner.Get("destination") };
    }
    public void finish_render(Control owner, Settings plan, string error)
    {
        owner.Set("busy", false); var button = Field<Button>(owner, "export_button"); if (GodotObject.IsInstanceValid(button)) button!.Disabled = false;
        var status = Field<Label>(owner, "status_label");
        if (GodotObject.IsInstanceValid(status)) status!.Text = error == "" ? "Exported · " + plan["destination"].AsString().GetFile() : error;
        if (error != "") GD.PushWarning(error);
        else
        {
            var files = GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd");
            if (files.Get("node").VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(files.Get("node").AsGodotObject())) files.Call("update_root_folder");
        }
    }
    public void progress(Control owner, int done, int total, string stage)
    {
        var status = Field<Label>(owner, "status_label"); if (GodotObject.IsInstanceValid(status)) status!.Text = $"{stage} · {done} / {total} frames";
    }
}
