using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

public partial class NaturalSourceUiTest : Node
{
    private static IEnumerable<Node> Descendants(Node root) { foreach (Node child in root.GetChildren()) { yield return child; foreach (var nested in Descendants(child)) yield return nested; } }
    private async Task Settle() { for (int i = 0; i < 5; i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
    private async Task FinishEdit(Control workspace)
    { await Settle(); for (int i = 0; i < 600; i++) { if (workspace.GetMeta("natural_edit", new Godot.Collections.Dictionary()).AsGodotDictionary().Count == 0) { await Settle(); return; } await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); } throw new Exception("Native source inspector edit did not complete."); }
    public override async void _Ready()
    {
        try
        {
            GetTree().Root.Size = new Vector2I(1400, 900); GetTree().Root.GuiEmbedSubwindows = true;
            var workspace = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace.gd").New().As<Control>(); AddChild(workspace); await Settle(); var session = workspace.Get("session").As<RefCounted>(); var item = session.Call("add", "Tree / Birch", new Godot.Collections.Dictionary { ["levels"] = 0, ["branches"] = 2 }).As<Resource>(); string id = item.Get("id").AsString(); await Settle();
            Resource Current() => session.Get("document").As<Resource>().Call("component", id).As<Resource>();
            var properties = workspace.Get("properties").As<Control>(); var heightLabel = Descendants(properties).OfType<Label>().Single(label => label.Text == "Height"); var height = heightLabel.GetParent().GetChildren().OfType<Control>().Last(); height.Set("value", 10.0); double expected = height.Get("value").AsDouble(); await FinishEdit(workspace);
            if (Math.Abs(Current().Get("parameters").AsGodotDictionary()["height"].AsDouble() - expected) > .001) throw new Exception("Height control did not regenerate its source: actual=" + Current().Get("parameters").AsGodotDictionary()["height"] + ", expected=" + expected + ", status=" + workspace.Get("status").As<Label>().Text); session.Call("undo"); await Settle(); if (Math.Abs(Current().Get("parameters").AsGodotDictionary()["height"].AsDouble() - 8) > .001) throw new Exception("Height control did not undo to Birch height."); GD.Print("PASS native source numeric control regenerates asynchronously and undoes");
            Descendants(properties).OfType<Button>().Single(button => button.Text == "Foliage").ButtonPressed = true; var folds = session.Get("document").As<Resource>().Get("workspace_state").AsGodotDictionary()["natural_folds"].AsGodotDictionary(); if (!folds[id + "Foliage"].AsBool()) throw new Exception("Native source fold did not persist."); GD.Print("PASS native source fold updates document workspace state");
            var before = Current().Get("mesh").As<Resource>().Get("vertices").AsVector3Array(); var season = Descendants(properties).OfType<OptionButton>().Single(option => option.ItemCount == 4 && option.GetItemText(0) == "Summer foliage"); season.EmitSignal(OptionButton.SignalName.ItemSelected, 2L); await Settle();
            if (Current().Get("parameters").AsGodotDictionary()["season"].AsInt32() != 2 || !before.SequenceEqual(Current().Get("mesh").As<Resource>().Get("vertices").AsVector3Array())) throw new Exception("Season control changed geometry or lost its value."); session.Call("undo"); await Settle(); GD.Print("PASS native season control changes appearance without touching geometry and undoes");
            Descendants(properties).OfType<Button>().Single(button => button.Text == "Edit individual branches…").EmitSignal(BaseButton.SignalName.Pressed); await Settle(); var popup = Descendants(workspace).OfType<Window>().Single(window => window.Title == "Branch structure"); var lengthLabel = Descendants(popup).OfType<Label>().Single(label => label.Text == "Length"); lengthLabel.GetParent().GetChildren().OfType<Control>().Last().Set("value", 1.5); await FinishEdit(workspace);
            var edits = Current().Get("parameters").AsGodotDictionary()["branch_overrides"].AsGodotDictionary(); if (Math.Abs(edits["b0"].AsGodotDictionary()["length"].AsDouble() - 1.5) > .001) throw new Exception("Branch popup numeric edit did not reach native regeneration."); GD.Print("PASS native branch popup changes the chosen branch through the source worker");
            popup.QueueFree(); var vine = session.Call("add", "Plant / Vine").As<Resource>(); string vineId = vine.Get("id").AsString(); await Settle();
            Descendants(properties).OfType<Button>().Single(button => button.Text == "Edit growth path / attachment…").EmitSignal(BaseButton.SignalName.Pressed); await Settle(); var pathWindow = Descendants(workspace).OfType<Window>().Single(window => window.Title == "Vine path");
            Resource Vine() => session.Get("document").As<Resource>().Call("component", vineId).As<Resource>();
            Descendants(pathWindow).OfType<Button>().Single(button => button.Text == "＋ Point").EmitSignal(BaseButton.SignalName.Pressed); await FinishEdit(workspace);
            if (Vine().Get("parameters").AsGodotDictionary()["growth_path"].AsVector3Array().Length != 4) throw new Exception("Native path Add Point did not persist the edited path.");
            Descendants(pathWindow).OfType<Button>().Single(button => button.Text == "− Point").EmitSignal(BaseButton.SignalName.Pressed); await FinishEdit(workspace);
            if (Vine().Get("parameters").AsGodotDictionary()["growth_path"].AsVector3Array().Length != 3) throw new Exception("Native path Remove Point did not persist the edited path."); GD.Print("PASS native vine path popup adds/removes points through undoable source generation");
            var surface = session.Call("add", "Box").As<Resource>(); var selected = session.Get("selected").AsGodotArray<string>(); selected.Clear(); selected.Add(vineId); selected.Add(surface.Get("id").AsString());
            Descendants(pathWindow).OfType<Button>().Single(button => button.Text == "Attach to other selected mesh").EmitSignal(BaseButton.SignalName.Pressed); await FinishEdit(workspace);
            if (Vine().Get("parameters").AsGodotDictionary()["growth_surface"].As<Resource>() == null) throw new Exception("Native vine attachment did not retain a surface snapshot.");
            Descendants(pathWindow).OfType<Button>().Single(button => button.Text == "Detach from surface").EmitSignal(BaseButton.SignalName.Pressed); await FinishEdit(workspace);
            if (Vine().Get("parameters").AsGodotDictionary()["growth_surface"].As<Resource>() != null) throw new Exception("Native vine detach did not clear its surface."); session.Call("undo"); await Settle(); if (Vine().Get("parameters").AsGodotDictionary()["growth_surface"].As<Resource>() == null) throw new Exception("Vine surface detach did not undo."); GD.Print("PASS native vine popup attaches/detaches a source surface and preserves undo");
            pathWindow.QueueFree(); workspace.QueueFree(); await Settle(); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
