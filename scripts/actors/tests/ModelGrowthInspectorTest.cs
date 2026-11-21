using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;

public partial class ModelGrowthInspectorTest : Node
{
    private Control _workspace = null!;
    private RefCounted _session = null!;
    private int _checks;
    private async Task Settle() { for (int i = 0; i < 6; i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
    private Resource Data() => _session.Call("primary").As<Resource>().Get("growth").As<Resource>();
    private Godot.Collections.Array Regions() => Data().Get("regions").AsGodotArray();
    private Control Properties() => _workspace.Get("properties").As<Control>();
    private Button FindButton(string text) => Properties().FindChildren("*", "Button", true, false).OfType<Button>().First(button => button.Text == text);
    private void Check(bool condition, string title) { if (!condition) throw new Exception(title); _checks++; GD.Print("PASS ", title); }
    public override async void _Ready()
    {
        try
        {
            GetTree().Root.Size = new Vector2I(1500, 950); GetTree().Root.GuiEmbedSubwindows = true;
            _workspace = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace.gd").New().As<Control>(); AddChild(_workspace); await Settle(); _session = _workspace.Get("session").As<RefCounted>();
            _session.Call("add", "Plane"); using var growth = new SurfaceGrowthGeometry(); Check(growth.add(_session, 0).Length == 0, "Native inspector fixture generates real hair"); await Settle();
            Properties().FindChildren("*", "CheckButton", true, false).OfType<CheckButton>().First(button => button.Name == "GrowthLocalAssignments").ButtonPressed = true; await Settle();
            var scope = Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount == 6 && input.GetItemText(0) == "Selected strand"); scope.Select(5); FindButton("Assign").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Regions().Count == 1 && Regions()[0].AsGodotDictionary()["roots"].AsInt32Array().Length == Data().Get("roots").AsGodotArray().Count, "Whole-component assignment includes every real strand");
            _session.Call("undo"); await Settle(); Check(Regions().Count == 0, "Region creation undoes in one step"); _session.Call("redo"); await Settle(); Check(Regions().Count == 1, "Region creation redoes with its material and mask");
            var style = Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount > 1 && input.GetItemText(0) == "Inherit component style");
            int curly = Enumerable.Range(1, style.ItemCount - 1).First(index => style.GetItemText(index) == "Curly"); style.Select(curly); style.EmitSignal(OptionButton.SignalName.ItemSelected, curly); await Settle();
            Check(Regions()[0].AsGodotDictionary()["style"].As<Resource>().Get("title").AsString() == "Curly", "Local style chooser updates the selected region"); _session.Call("undo"); await Settle(); Check(Regions()[0].AsGodotDictionary()["style"].AsGodotObject() == null, "Local style chooser preserves undo");
            var pickers = Properties().FindChildren("*", "ColorPickerButton", true, false).OfType<ColorPickerButton>().ToArray(); var picker = pickers[^2]; Color before = picker.Color;
            picker.Color = Colors.Red; picker.EmitSignal(ColorPickerButton.SignalName.ColorChanged, Colors.Red); picker.EmitSignal(ColorPickerButton.SignalName.PopupClosed); await Settle();
            Check(Regions()[0].AsGodotDictionary()["material"].As<Resource>().Get("root_color").AsColor() == Colors.Red, "Local color edit updates the region material"); _session.Call("undo"); await Settle();
            Check(Regions()[0].AsGodotDictionary()["material"].As<Resource>().Get("root_color").AsColor() == before, "Local color edit restores its original color on undo");
            Properties().FindChildren("*", "CheckButton", true, false).OfType<CheckButton>().First(button => button.Name == "GrowthGroomMode").ButtonPressed = true; await Settle();
            var presets = Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount > 0 && input.GetItemText(0) == "Brush presets");
            presets.GetParent().GetChildren().OfType<Button>().First(button => button.Text == "Save").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("brush_presets").AsGodotArray().Count == 1, "Brush preset Save creates the first preset");
            presets = Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount > 0 && input.GetItemText(0) == "Brush presets"); presets.GetParent().GetChildren().OfType<Button>().First(button => button.Text == "Save").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("brush_presets").AsGodotArray().Count == 1, "Brush preset Save updates the active preset without duplicating it");
            presets = Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount > 0 && input.GetItemText(0) == "Brush presets"); presets.GetParent().GetChildren().OfType<Button>().First(button => button.Text == "+").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("brush_presets").AsGodotArray().Count == 2, "Brush preset plus creates another editable preset"); _session.Call("undo"); await Settle(); Check(Data().Get("brush_presets").AsGodotArray().Count == 1, "Brush preset creation participates in undo");
            OptionButton Section() => Properties().FindChildren("*", "OptionButton", true, false).OfType<OptionButton>().First(input => input.ItemCount > 0 && input.GetItemText(0) == "Color & highlights");
            var section = Section(); section.Select(3); section.EmitSignal(OptionButton.SignalName.ItemSelected, 3); await Settle(); FindButton("Noise").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("appearance").As<Resource>().Get("albedo_texture").AsGodotObject() is NoiseTexture2D, "Texture panel creates an editable noise texture");
            Properties().FindChildren("*", "CheckButton", true, false).OfType<CheckButton>().First(input => input.Text == "Noise as normal map").ButtonPressed = true; await Settle();
            Check(Data().Get("appearance").As<Resource>().Get("albedo_texture").As<NoiseTexture2D>().AsNormalMap, "Noise normal-map toggle changes the real texture"); _session.Call("undo"); await Settle();
            Check(!Data().Get("appearance").As<Resource>().Get("albedo_texture").As<NoiseTexture2D>().AsNormalMap, "Noise normal-map edits preserve undo");
            section = Section(); section.Select(5); section.EmitSignal(OptionButton.SignalName.ItemSelected, 5); await Settle(); FindButton("Create multicolor gradient").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("appearance").As<Resource>().Get("gradient").As<Gradient>().GetPointCount() == 2, "Gradient section creates root and tip color stops"); FindButton("Add gradient stop").EmitSignal(Button.SignalName.Pressed); await Settle();
            Check(Data().Get("appearance").As<Resource>().Get("gradient").As<Gradient>().GetPointCount() == 3, "Gradient section inserts another editable stop"); _session.Call("undo"); await Settle();
            Check(Data().Get("appearance").As<Resource>().Get("gradient").As<Gradient>().GetPointCount() == 2, "Gradient stop insertion preserves undo");
            var operations = new ModelWorkspaceOperations(); operations.growth_save_material(_workspace, Data()); await Settle();
            string materialPath = ProjectSettings.GlobalizePath("res://.godot/verification/native-growth-inspector-material.tres");
            _workspace.FindChildren("*", "FileDialog", true, false).OfType<FileDialog>().Last().EmitSignal(FileDialog.SignalName.FileSelected, materialPath); await Settle();
            Check(Godot.FileAccess.FileExists(materialPath) && ResourceLoader.Load(materialPath) is Resource savedMaterial && savedMaterial.Get("gradient").As<Gradient>() != null, "Material save dialog writes the authored resource in the chosen project location");
            Data().Set("growth_style", new GrowthMaterialOperations().style_preset("Curly")); operations.growth_save_style(_workspace, Data()); await Settle();
            string stylePath = ProjectSettings.GlobalizePath("res://.godot/verification/native-growth-inspector-style.tres");
            _workspace.FindChildren("*", "FileDialog", true, false).OfType<FileDialog>().Last().EmitSignal(FileDialog.SignalName.FileSelected, stylePath); await Settle();
            Check(Godot.FileAccess.FileExists(stylePath) && ResourceLoader.Load(stylePath) is Resource savedStyle && savedStyle.Get("title").AsString() == "Curly", "Style save dialog preserves the selected style resource");
            DirAccess.RemoveAbsolute(materialPath); DirAccess.RemoveAbsolute(stylePath);
            _workspace.QueueFree(); await Settle(); _session = null!; GD.Print("NATIVE GROWTH INSPECTOR: ", _checks, " checks, 0 failures"); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
