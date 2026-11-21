using Godot;
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

/// <summary>Frame rendering and media encoding. This never packages the application.</summary>
public partial class CompositeWorkspaceExporter : Node
{
    [Signal] public delegate void progressEventHandler(string message);
    [Signal] public delegate void completedEventHandler(bool success);
    public bool busy { get; private set; }
    private CancellationTokenSource? _cancellation;
    public override void _ExitTree() => _cancellation?.Cancel();

    public bool start_export(Resource document, string destination, string format, string encoder)
    {
        if (busy || !IsInsideTree()) return false;
        busy = true; _cancellation = new CancellationTokenSource();
        _ = Run((Resource)document.Duplicate(true), destination, format.ToLowerInvariant(), encoder, _cancellation.Token);
        return true;
    }

    private void Report(string message) { if (IsInsideTree()) EmitSignal(SignalName.progress, message); }
    private async Task Run(Resource document, string destination, string format, string encoder, CancellationToken cancellation)
    {
        string? temporary = null; string? encodedFile = null; bool success = false;
        try
        {
            using var snapshot = document;
            // Let callers subscribe to completion before validation can fail.
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            cancellation.ThrowIfCancellationRequested();
            if (format is not ("mp4" or "png" or "exr")) throw new InvalidOperationException("Choose PNG, EXR, or MP4 output.");
            if (format == "mp4" && string.IsNullOrWhiteSpace(encoder)) throw new InvalidOperationException("Video export requires FFmpeg.");
            double rate = document.Get("frame_rate").AsDouble(), duration = document.Get("duration").AsDouble();
            if (!double.IsFinite(rate) || rate <= 0 || !double.IsFinite(duration) || duration < 0 || duration * rate > int.MaxValue)
                throw new InvalidOperationException("The composition duration or frame rate is invalid.");
            int frames = Math.Max(1, (int)Math.Ceiling(duration * rate));
            string absolute = ProjectSettings.GlobalizePath(destination);
            string safeTitle = document.Get("title").AsString().Trim();
            foreach (char invalid in ":/\\?*\"|%<>") safeTitle = safeTitle.Replace(invalid, '_');
            string prefix = safeTitle + "_";
            string directory;
            if (format == "mp4")
            {
                temporary = ProjectSettings.GlobalizePath("res://.godot/compositing_render_" + Guid.NewGuid().ToString("N"));
                directory = temporary; prefix = "frame_";
            }
            else directory = absolute;
            Directory.CreateDirectory(directory);
            string Frame(int index) => Path.Combine(directory, prefix + index.ToString("D6", CultureInfo.InvariantCulture) + "." + (format == "exr" ? "exr" : "png"));
            if (format != "mp4")
                for (int i = 0; i < frames; i++) if (File.Exists(Frame(i))) throw new InvalidOperationException("Sequence files already exist. Choose another directory.");
            using var evaluator = new CompositingEvaluator(); using var preview = new CompositeWorkspacePreview();
            for (int i = 0; i < frames; i++)
            {
                cancellation.ThrowIfCancellationRequested(); evaluator.clear_cache();
                CompositeBuffer? buffer = evaluator.evaluate(document, i / rate, false);
                var waiting = Stopwatch.StartNew();
                while (buffer == null && evaluator.last_error.StartsWith("Waiting for the requested video frame:", StringComparison.Ordinal) && waiting.Elapsed.TotalSeconds < 30)
                {
                    await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); cancellation.ThrowIfCancellationRequested();
                    evaluator.clear_cache(); buffer = evaluator.evaluate(document, i / rate, false);
                }
                if (buffer?.image == null) throw new InvalidOperationException("Render stopped at frame " + i + ": " + evaluator.last_error);
                using (buffer)
                {
                    using var image = format == "exr" ? (Image)buffer.image.Duplicate() : preview.display_preview(buffer.image);
                    Error error = format == "exr" ? image.SaveExr(Frame(i), false) : image.SavePng(Frame(i));
                    if (error != Error.Ok) throw new IOException("Could not write frame " + i + ": " + error);
                }
                Report("Rendering frame " + (i + 1) + " / " + frames);
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            }
            if (format == "mp4")
            {
                // Encode beside the destination; replace it only after a successful encode.
                encodedFile = absolute + "." + Guid.NewGuid().ToString("N") + ".mp4";
                var start = new ProcessStartInfo(encoder) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
                foreach (string argument in new[] { "-nostdin", "-v", "error", "-y", "-framerate", rate.ToString(CultureInfo.InvariantCulture), "-start_number", "0", "-i", Path.Combine(directory, "frame_%06d.png"), "-frames:v", frames.ToString(CultureInfo.InvariantCulture), "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", encodedFile }) start.ArgumentList.Add(argument);
                Report("Encoding video…");
                using var process = Process.Start(start) ?? throw new IOException("Could not start FFmpeg.");
                using var registration = cancellation.Register(() => { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } });
                var stderr = process.StandardError.ReadToEndAsync(cancellation); var stdout = process.StandardOutput.ReadToEndAsync(cancellation);
                await process.WaitForExitAsync(cancellation); string errors = await stderr; await stdout;
                if (process.ExitCode != 0 || !File.Exists(encodedFile)) throw new IOException("FFmpeg: " + errors);
                File.Move(encodedFile, absolute, true); encodedFile = null;
            }
            success = true; Report(format == "mp4" ? "Video exported · silent MP4 · " + destination : "Exported " + format.ToUpperInvariant() + " sequence · " + destination);
        }
        catch (OperationCanceledException) { Report("Export cancelled."); }
        catch (Exception error) { Report("Export failed: " + error.Message); }
        finally
        {
            // Both paths are unique to this job; never clean the user's sequence directory.
            try { if (encodedFile != null && File.Exists(encodedFile)) File.Delete(encodedFile); if (temporary != null && Directory.Exists(temporary)) Directory.Delete(temporary, true); }
            catch (IOException error) { GD.PushWarning("Could not clean temporary render files: " + error.Message); }
            busy = false; _cancellation?.Dispose(); _cancellation = null;
            if (IsInsideTree()) EmitSignal(SignalName.completed, success);
        }
    }
}
