using Godot;
using System;
using System.IO;
using System.Threading.Tasks;

public partial class CompositorExporterTest : Node
{
    public override void _Ready() => _ = Run();
    private async Task Run()
    {
        string folder = ProjectSettings.GlobalizePath("res://.godot/verification/exporter_" + Guid.NewGuid().ToString("N"));
        try
        {
            using var document = new CompositingDocument { title = "Snapshot", canvas_size = new Vector2I(3, 3), duration = .25, frame_rate = 8 };
            var layer = (CompositeLayer)document.add_layer(1, "Solid"); layer.color = Colors.Red;
            var exporter = new CompositeWorkspaceExporter(); AddChild(exporter);
            if (!exporter.start_export(document, folder, "png", "")) throw new Exception("Initial export rejected.");
            if (exporter.start_export(document, folder, "png", "")) throw new Exception("Concurrent export accepted.");
            layer.color = Colors.Blue;
            var done = await ToSignal(exporter, CompositeWorkspaceExporter.SignalName.completed);
            using var frame = Image.LoadFromFile(Path.Combine(folder, "Snapshot_000000.png"));
            if (!done[0].AsBool() || frame == null || frame.GetPixel(0, 0).R < .99f || frame.GetPixel(0, 0).B > .01f || exporter.busy) throw new Exception("Export did not preserve its initial document snapshot.");
            byte[] original = File.ReadAllBytes(Path.Combine(folder, "Snapshot_000000.png"));
            exporter.start_export(document, folder, "png", ""); done = await ToSignal(exporter, CompositeWorkspaceExporter.SignalName.completed);
            if (done[0].AsBool() || !original.AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(folder, "Snapshot_000000.png")))) throw new Exception("Sequence overwrite guard failed.");
            exporter.start_export(document, folder, "unknown", ""); done = await ToSignal(exporter, CompositeWorkspaceExporter.SignalName.completed);
            if (done[0].AsBool()) throw new Exception("Unsupported output format accepted.");
            string target = Path.Combine(folder, "preserve.mp4"); File.WriteAllText(target, "existing output");
            exporter.start_export(document, target, "mp4", Path.Combine(folder, "missing-encoder.exe")); done = await ToSignal(exporter, CompositeWorkspaceExporter.SignalName.completed);
            if (done[0].AsBool() || File.ReadAllText(target) != "existing output" || Directory.GetFiles(folder, "*.mp4").Length != 1) throw new Exception("Failed encoding altered the destination or left a partial output.");
            document.frame_rate = 0;
            exporter.start_export(document, folder, "png", ""); done = await ToSignal(exporter, CompositeWorkspaceExporter.SignalName.completed);
            if (done[0].AsBool()) throw new Exception("Invalid frame rate accepted.");
            GD.Print("PASS native media exporter snapshot isolation, concurrent job guard, overwrite protection, unsupported format, failed encoder protection and invalid timing");
            exporter.QueueFree(); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }
}
