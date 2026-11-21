using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;

public partial class ModelSculptViewportTest : Node
{
    private async Task Settle() { for (int i = 0; i < 5; i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
    public override async void _Ready()
    {
        try
        {
            GetTree().Root.Size = new Vector2I(1200, 800); GetTree().Root.GuiEmbedSubwindows = true;
            var workspace = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace.gd").New().As<Control>(); AddChild(workspace);
            workspace.Call("open_source", new KiwiModelDocument());
            var session = workspace.Get("session").As<RefCounted>(); session.Call("add", "Box"); var canvas = workspace.Get("canvas").As<Control>(); canvas.Call("set_view", "Front"); canvas.Call("frame", false); await Settle();
            var transforms = canvas.Get("_transforms_native").As<ModelViewportTransforms>(); var picking = canvas.Get("_picking_native").As<ModelViewportPicking>();
            canvas.Set("radius", 4f); canvas.Set("strength", .6f);
            foreach (string tool in new[] { "Grab", "Inflate", "Smooth", "Flatten", "Pinch" })
            {
                var item = session.Call("primary").As<Resource>(); Vector3[] before = item.Get("mesh").As<Resource>().Get("vertices").AsVector3Array();
                canvas.Set("sculpt", tool); Vector2 point = picking.project(canvas, Vector3.Zero); session.Call("begin"); transforms.sculpt_at(canvas, point, point - new Vector2(15, 0), false);
                Vector3[] after = session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array();
                if (before.SequenceEqual(after) || after.Any(p => !p.IsFinite())) throw new Exception(tool + " did not produce a valid visible sculpt change.");
                session.Call("commit", "Test " + tool); session.Call("undo");
                if (!before.SequenceEqual(session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array())) throw new Exception(tool + " did not undo exactly.");
                session.Call("redo"); if (!after.SequenceEqual(session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array())) throw new Exception(tool + " did not redo exactly.");
                session.Call("undo"); await Settle(); GD.Print("PASS native " + tool + " sculpt changes vertices and preserves exact undo/redo");
            }
            canvas.Set("sculpt", "Inflate"); var original = session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array(); Vector2 center = picking.project(canvas, Vector3.Zero);
            session.Call("begin"); transforms.sculpt_at(canvas, center, center, true); session.Call("cancel");
            if (!original.SequenceEqual(session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array())) throw new Exception("Cancelled subtract sculpt did not restore vertices.");
            GD.Print("PASS cancel subtract sculpt restores the exact mesh"); workspace.QueueFree(); await Settle(); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
