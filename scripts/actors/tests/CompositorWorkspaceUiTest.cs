using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class CompositorWorkspaceUiTest : Node
{
    private static IEnumerable<Node> Descendants(Node root)
    {
        foreach (Node child in root.GetChildren()) { yield return child; foreach (Node nested in Descendants(child)) yield return nested; }
    }
    public override void _Ready() => _ = Run();
    private async Task Run()
    {
        Control? workspace = null;
        try
        {
            workspace = new CompositingWorkspace(); AddChild(workspace);
            using var document = new CompositingDocument { canvas_size = new Vector2I(4, 4), duration = 1, frame_rate = 4 };
            var layer = (CompositeLayer)document.add_layer(1, "Editable"); workspace.Call("open_source", document, new Godot.Collections.Dictionary());
            workspace.Set("selected_id", layer.id); workspace.Call("_refresh_inspector");
            var inspector = workspace.Get("inspector").As<Control>(); SpinBox? opacity = null;
            foreach (Node node in Descendants(inspector))
                if (node is HBoxContainer row && row.GetChildCount() == 2 && row.GetChild(0) is Label label && label.Text == "Opacity") opacity = row.GetChild(1) as SpinBox;
            if (opacity == null) throw new Exception("Opacity control missing.");
            opacity.Value = .4;
            if (Math.Abs(workspace.Get("document").As<CompositingDocument>().layer(layer.id)!.Get("opacity").AsDouble() - .4) > .0001) throw new Exception("Inspector numeric control failed to edit the bound layer.");
            workspace.Call("undo");
            if (Math.Abs(workspace.Get("document").As<CompositingDocument>().layer(layer.id)!.Get("opacity").AsDouble() - 1) > .0001) throw new Exception("Inspector control edit failed undo.");
            workspace.Call("redo");
            if (Math.Abs(workspace.Get("document").As<CompositingDocument>().layer(layer.id)!.Get("opacity").AsDouble() - .4) > .0001) throw new Exception("Inspector control edit failed redo.");
            Button? nodesButton = null;
            foreach (Node node in Descendants(workspace)) if (node is Button button && button.Text == "Nodes") nodesButton = button;
            if (nodesButton == null) throw new Exception("Native toolbar mode button missing.");
            nodesButton.EmitSignal(Button.SignalName.Pressed);
            if (workspace.Get("mode").AsInt32() != 1) throw new Exception("Native toolbar failed mode switching.");
            Button? blurButton = null;
            foreach (Node node in Descendants(workspace)) if (node is Button button && button.Text == "Blur") blurButton = button;
            if (blurButton == null) throw new Exception("Native toolbar node button missing.");
            blurButton.EmitSignal(Button.SignalName.Pressed);
            var currentDocument = workspace.Get("document").As<CompositingDocument>();
            var currentGraph = (CompositeGraph)currentDocument.graphs[0]; string selectedNode = workspace.Get("selected_graph_node_id").AsString();
            SpinBox? radius = null;
            foreach (Node node in Descendants(inspector))
                if (node is HBoxContainer row && row.GetChildCount() == 2 && row.GetChild(0) is Label label && label.Text == "Radius") radius = row.GetChild(1) as SpinBox;
            if (radius == null) throw new Exception("Native graph inspector radius control missing.");
            radius.Value = 7;
            if (currentGraph.node(selectedNode)!.Get("settings").AsGodotDictionary()["radius"].AsInt32() != 7) throw new Exception("Native graph inspector failed settings edit.");
            workspace.Call("undo");
            currentDocument = workspace.Get("document").As<CompositingDocument>();
            if (((CompositeGraph)currentDocument.graphs[0]).node(selectedNode)!.Get("settings").AsGodotDictionary()["radius"].AsInt32() != 2) throw new Exception("Native graph setting failed undo.");
            using var playback = new CompositeWorkspacePlayback(); var spin = workspace.Get("time_spin").As<SpinBox>(); var slider = workspace.Get("time_slider").As<HSlider>(); var timer = workspace.Get("play_timer").As<Timer>();
            playback.configure(document, timer, spin, slider, .75);
            if (playback.advance(document, spin, slider, .75) != 1 || playback.advance(document, spin, slider, 1) != 0 || playback.seek(document, spin, slider, -1) != 0 || playback.seek(document, spin, slider, 20) != 1) throw new Exception("Native playback boundary or wrap failed.");
            workspace.Call("_rename_document", "Renamed composition"); workspace.Call("undo");
            if (workspace.Get("document").As<Resource>().Get("title").AsString() == "Renamed composition") throw new Exception("Nonempty document rename did not enter undo history.");
            workspace.Call("redo");
            if (workspace.Get("document").As<Resource>().Get("title").AsString() != "Renamed composition") throw new Exception("Document rename did not redo.");
            workspace.Call("open_source", document, new Godot.Collections.Dictionary { ["mode"] = 1, ["preview_time"] = .5 });
            if (!workspace.Get("graph_edit").As<GraphEdit>().Visible || !workspace.Get("graph_search").As<LineEdit>().Visible || workspace.Get("preview_time").AsDouble() != .5) throw new Exception("Restored workspace mode/time did not reach its controls.");
            var rows = new VBoxContainer(); AddChild(rows); var operation = new ImageOperationRow { index = 2 }; rows.AddChild(operation); int movedFrom = -1, movedTo = -1;
            operation.reorder_requested += (from, to) => { movedFrom = from; movedTo = to; };
            var payload = new Godot.Collections.Dictionary { ["owner"] = rows.GetInstanceId(), ["value_operation"] = 0 };
            if (!operation._CanDropData(Vector2.Zero, payload)) throw new Exception("Valid operation drag rejected.");
            operation._DropData(Vector2.Zero, payload);
            if (movedFrom != 0 || movedTo != 2) throw new Exception("Operation row did not request the correct reorder.");
            payload["owner"] = GetInstanceId();
            if (operation._CanDropData(Vector2.Zero, payload) || operation._CanDropData(Vector2.Zero, 42)) throw new Exception("Foreign or malformed operation payload accepted.");
            rows.QueueFree(); GD.Print("PASS native image operation reorder signal and drag ownership validation");
            using var hints = new InteractionHints(); using var firstOwner = new RefCounted(); using var secondOwner = new RefCounted(); string hint = "";
            hints.changed += value => hint = value; hints.set_idle("Idle"); hints.begin(firstOwner, "First"); hints.begin(secondOwner, "Second");
            if (hint != "Second") throw new Exception("Interaction hint priority failed.");
            hints.begin(firstOwner, "Updated"); hints.end(firstOwner);
            if (hint != "Second") throw new Exception("Ending an updated hint did not restore the previous context.");
            hints.end(secondOwner); if (hint != "Idle") throw new Exception("Interaction hints failed idle restoration.");
            GD.Print("PASS native interaction hint priority, owner replacement and context restoration");
            GD.Print("PASS actual layer/graph inspector value edits and undo/redo, toolbar mode/node actions, native playback seek clamping and looping");
            workspace.QueueFree(); await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); workspace?.QueueFree(); GetTree().Quit(1); }
    }
}
