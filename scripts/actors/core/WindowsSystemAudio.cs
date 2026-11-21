using Godot;
using Settings = Godot.Collections.Dictionary;

/// <summary>Frame-driven WASAPI capture without a GDScript coroutine driver.</summary>
[GlobalClass]
public partial class WindowsSystemAudio : Node
{
    [Signal] public delegate void start_completedEventHandler(string error);
    [Signal] public delegate void stop_completedEventHandler(Variant stream);
    [Signal] public delegate void file_stop_completedEventHandler(Settings result);

    public int pid { get; set; } = -1;
    public string directory { get; set; } = "";
    public int rate { get; set; } = 48000;
    public long _cursor { get; set; } = 44;
    public bool preserve_capture { get; set; }
    public string output_path { get; set; } = "";

    private enum Phase { Idle, Starting, Stopping, StoppingToFile }
    private Phase _phase;
    private ulong _deadline;
    private string _destination = "";
    private readonly WindowsSystemAudioOperations _operations = new();

    public Variant start() => start("");
    public Variant start(string destination)
    {
        if (_phase != Phase.Idle || pid > 0)
            return "System audio capture is already active.";
        var request = _operations.prepare_start(this, destination);
        string error = request["error"].AsString();
        if (error.Length > 0) return error;
        _deadline = request["deadline"].AsUInt64();
        if (!_operations.startup_pending(this, _deadline))
            return _operations.complete_start(this);
        _phase = Phase.Starting;
        SetProcess(true);
        return Variant.From(new Signal(this, SignalName.start_completed));
    }

    public Vector2[] samples() => _operations.samples(this);

    public Variant stop()
    {
        CancelPending();
        _deadline = _operations.prepare_stop(this);
        if (!_operations.stop_pending(this, _deadline))
            return Variant.From(_operations.complete_stop(this));
        _phase = Phase.Stopping;
        SetProcess(true);
        return Variant.From(new Signal(this, SignalName.stop_completed));
    }

    public Variant stop_to_file(string destination)
    {
        CancelPending();
        _destination = destination;
        _deadline = _operations.prepare_stop(this);
        if (!_operations.stop_pending(this, _deadline))
            return _operations.complete_stop_file(this, destination);
        _phase = Phase.StoppingToFile;
        SetProcess(true);
        return Variant.From(new Signal(this, SignalName.file_stop_completed));
    }

    public override void _Process(double delta)
    {
        var pending = _phase;
        if (pending == Phase.Idle) { SetProcess(false); return; }
        bool waiting = pending == Phase.Starting
            ? _operations.startup_pending(this, _deadline)
            : _operations.stop_pending(this, _deadline);
        if (waiting) return;
        _phase = Phase.Idle;
        SetProcess(false);
        switch (pending)
        {
            case Phase.Starting:
                EmitSignal(SignalName.start_completed, _operations.complete_start(this));
                break;
            case Phase.Stopping:
                EmitSignal(SignalName.stop_completed, Variant.From(_operations.complete_stop(this)));
                break;
            case Phase.StoppingToFile:
                EmitSignal(SignalName.file_stop_completed, _operations.complete_stop_file(this, _destination));
                break;
        }
    }

    private void CancelPending()
    {
        var pending = _phase;
        _phase = Phase.Idle;
        SetProcess(false);
        switch (pending)
        {
            case Phase.Starting:
                EmitSignal(SignalName.start_completed, "System audio capture was cancelled.");
                break;
            case Phase.Stopping:
                EmitSignal(SignalName.stop_completed, default(Variant));
                break;
            case Phase.StoppingToFile:
                EmitSignal(SignalName.file_stop_completed, new Settings { ["error"] = "System audio capture was cancelled.", ["path"] = "" });
                break;
        }
    }

    public void request_stop() => _operations.request_stop(this);
    public void cleanup()
    {
        _operations.cleanup(this);
        CancelPending();
    }
    public override void _ExitTree()
    {
        _operations.exit_tree(this);
        CancelPending();
    }
}
