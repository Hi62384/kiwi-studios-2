using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiAudioJobs : Node
{
    [Signal] public delegate void completedEventHandler(string kind, long generation, Variant result);
    [Signal] public delegate void progress_changedEventHandler(double value, string description);
    public GodotThread? _thread { get; set; }
    public Settings _current { get; set; } = new();
    public Godot.Collections.Array<Settings> _queue { get; set; } = new();
    private readonly AudioJobsOperations _operations = new();
    public RefCounted _new_work() => new AudioWorkToken();
    public Error _start_work(GodotThread thread, Variant operation, RefCounted work)
    {
        // Preserve an incoming engine Callable while its owning job is retained.
        return thread.Start(Callable.From<Variant>(() =>
        {
            using var arguments = new Godot.Collections.Array { work };
            return EngineVariantDispatch.InvokeCallable(operation, arguments);
        }));
    }
    public void request(string kind, Variant operation) => request(kind, operation, 0, true);
    public void request(string kind, Variant operation, long generation) => request(kind, operation, generation, true);
    public void request(string kind, Variant operation, long generation, bool replace) => _operations.request(this, kind, operation, generation, replace);
    public void cancel_kind(string kind) => _operations.cancel_kind(this, kind);
    public bool busy() => _operations.busy(this);
    public void cancel_all() => _operations.cancel_all(this);
    public override void _Process(double delta) => _operations.process(this);
    public override void _ExitTree() => _operations.exit_tree(this);
}
