using Godot;
using System.Threading;
using Settings = Godot.Collections.Dictionary;

public partial class RigWeightJob : RefCounted
{
    public Godot.Collections.Array<Settings> tasks { get; set; } = new();
    public string method { get; set; } = "Smooth";
    public int influences { get; set; } = 4;
    private int _cancelled;
    // Resolve on construction in the main thread, before the UI starts its worker.
    private readonly RigWeighting _weighting = new();
    public void cancel() => Interlocked.Exchange(ref _cancelled, 1);
    public bool is_cancelled() => Volatile.Read(ref _cancelled) != 0;
    public Settings run()
    {
        var result = new Settings();
        foreach (var task in tasks)
        {
            if (is_cancelled()) return new Settings();
            var binding = _weighting.compute(task["source"].As<Mesh>(), task["bones"].AsGodotArray(), task["transform"].AsTransform3D(), method, influences, 8, this);
            if (binding == null) return new Settings();
            result[task["id"].AsString()] = binding;
        }
        return is_cancelled() ? new Settings() : result;
    }
}
