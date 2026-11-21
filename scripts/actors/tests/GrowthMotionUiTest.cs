using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings = Godot.Collections.Dictionary;

public partial class GrowthMotionUiTest : Node
{
    private int _checks;
    private async Task Settle() { for (int i = 0; i < 5; i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
    private void Check(bool condition, string title) { if (!condition) throw new Exception(title); _checks++; GD.Print("PASS ", title); }
    public override async void _Ready()
    {
        try
        {
            GetTree().Root.Size = new Vector2I(1400, 900); GetTree().Root.GuiEmbedSubwindows = true;
            var session = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_session.gd").New().As<RefCounted>(); session.Call("add", "Plane"); using var growth = new SurfaceGrowthGeometry(); growth.add(session, 0);
            var component = session.Call("primary").As<Resource>(); component.Set("title", "Motion UI hair"); string path = "user://native-growth-motion-ui.tres"; ResourceSaver.Save(session.Get("document").As<Resource>(), path);
            var editor = GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/Timeline/timeline_editor.gd").New().As<Control>(); AddChild(editor); var viewport = new SubViewport { OwnWorld3D = true, Size = new Vector2I(600, 400) }; AddChild(viewport); var holder = new Node3D(); viewport.AddChild(holder); editor.Set("runtime_holder", holder);
            var model = editor.Get("model").As<RefCounted>(); var registry = editor.Get("registry").As<RefCounted>(); model.Call("create_actor", registry.Call("get_definition", new StringName("basic_mesh")), 0, new Settings { [new StringName("mesh_path")] = path }); await Settle();
            var actor = model.Get("actors").AsGodotArray().Select(value => value.As<Resource>()).First(value => value.Get("display_name").AsString() == "Motion UI hair");
            actor.Get("values").AsGodotDictionary()["physics"] = new Settings { ["enabled"] = true, ["gravity"] = 2.0, ["wind"] = new Vector3(1, 0, 0), ["collision"] = false, ["particles"] = 3, ["recovery"] = 5.0, ["radius"] = .01 };
            var physics = editor.Get("physics").As<RefCounted>(); physics.Call("mark_dirty"); editor.Get("canvas").As<Control>().Set("playhead", .2); editor.Call("_evaluate_runtimes"); int frames = 0;
            while (physics.Get("pending").AsBool() && frames++ < 900) { await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); editor.Call("_evaluate_runtimes"); }
            Check(!physics.Get("pending").AsBool(), "Motion UI fixture completes deterministic guide simulation");
            using var operations = new GrowthPhysicsOperations(); operations.open(editor, actor, this); await Settle(); var popup = GetNode<AcceptDialog>("GrowthMotionCorrections"); var list = popup.FindChildren("*", "ItemList", true, false).OfType<ItemList>().Single();
            Check(list.ItemCount == 3, "Motion correction dialog lists the actual simulated guides"); list.Select(1, false); list.EmitSignal(ItemList.SignalName.MultiSelected, 1, true); await Settle();
            var label = popup.FindChildren("*", "Label", true, false).OfType<Label>().First(input => input.Text == "Root-local offset"); var line = label.GetParent().GetChild<HBoxContainer>(label.GetIndex() + 1); var x = line.GetChildren().OfType<SpinBox>().First(); x.Value = .35; await Settle();
            string[] ids = list.GetSelectedItems().Select(index => list.GetItemMetadata(index).AsString()).ToArray();
            Settings Corrections() => actor.Get("values").AsGodotDictionary()["growth_overrides"].AsGodotDictionary();
            Check(ids.Length == 2 && ids.All(id => Mathf.IsEqualApprox(Corrections()[id].AsGodotDictionary()["offset"].AsVector3().X, .35f)), "One correction field edits every selected guide");
            model.Call("undo"); await Settle(); Check(!actor.Get("values").AsGodotDictionary().TryGetValue("growth_overrides", out var undo) || undo.AsGodotDictionary().Count == 0, "Multi-guide correction undoes as one action"); model.Call("redo"); await Settle();
            Check(ids.All(id => Mathf.IsEqualApprox(Corrections()[id].AsGodotDictionary()["offset"].AsVector3().X, .35f)), "Multi-guide correction redo restores every selected guide");
            line.GetChildren().OfType<Button>().Single().EmitSignal(Button.SignalName.Pressed); await Settle();
            var tracks = actor.Get("animation_tracks").AsGodotArray(); Check(ids.All(id => tracks.Any(value => value.As<Resource>().Get("path").AsStringArray().SequenceEqual(new[] { "growth_overrides", id, "offset" }))), "Correction diamond inserts a separate track for each selected guide");
            model.Call("undo"); await Settle(); Check(actor.Get("animation_tracks").AsGodotArray().Count == 0, "Multi-guide keyframe insertion undoes in one step");
            popup.QueueFree(); physics.Call("dispose"); model.Get("history").As<GodotObject>().Call("clear_history"); editor.QueueFree(); viewport.QueueFree(); await Settle(); DirAccess.RemoveAbsolute(path);
            GD.Print("NATIVE GROWTH MOTION UI: ", _checks, " checks, 0 failures"); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
