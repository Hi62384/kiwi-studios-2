using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorScreenRecorder : Node
{
    [Signal] public delegate void start_completedEventHandler(string error);
    [Signal] public delegate void stop_completedEventHandler(string path);
    public bool recording {get;set;}
    public Settings process {get;set;} = new();
    public string directory {get;set;} = "";
    public string output_path {get;set;} = "";
    public ActorAudioRecorder? audio_recorder {get;set;}
    public double _audio_lead {get;set;}
    public string last_error {get;set;} = "";
    private readonly ActorScreenRecorderOperations _operations = new();
    private enum Phase {Idle,AudioStart,CaptureStart,CaptureStop,AudioStop,Mux}
    private Phase _phase;
    private Settings _request = new();
    private Settings _options = new();
    private Settings _capture = new();
    private Settings _mux = new();
    private ulong _deadline;
    private GodotObject? _audioCompletionOwner;
    private StringName _audioCompletionName="";
    private Callable _audioCompletionCallback;
    private bool ObserveAudio(Variant completion,StringName method)
    {
        DisconnectAudioCompletion();
        var signal=completion.AsSignal();
        if (!GodotObject.IsInstanceValid(signal.Owner)) return false;
        _audioCompletionOwner=signal.Owner;
        _audioCompletionName=signal.Name;
        _audioCompletionCallback=new Callable(this,method);
        if (_audioCompletionOwner.Connect(_audioCompletionName,_audioCompletionCallback,(uint)ConnectFlags.OneShot)==Error.Ok) return true;
        _audioCompletionOwner=null;
        return false;
    }
    private void DisconnectAudioCompletion()
    {
        var owner=_audioCompletionOwner;
        _audioCompletionOwner=null;
        if (GodotObject.IsInstanceValid(owner) && owner!.IsConnected(_audioCompletionName,_audioCompletionCallback))
            owner.Disconnect(_audioCompletionName,_audioCompletionCallback);
    }
    private void AudioStarted(string error)
    {
        if (_phase!=Phase.AudioStart) return;
        DisconnectAudioCompletion();
        _phase=Phase.Idle;
        var result=BeginCapture(error);
        if (result.VariantType!=Variant.Type.Signal) EmitSignal(SignalName.start_completed,result);
    }
    private void AudioStopped(Variant audio)
    {
        if (_phase!=Phase.AudioStop) return;
        DisconnectAudioCompletion();
        _phase=Phase.Idle;
        var result=BeginMux(audio);
        if (result.VariantType!=Variant.Type.Signal) EmitSignal(SignalName.stop_completed,result);
    }


    public static Godot.Collections.Array<Settings> targets()
    {using var operations=new ActorScreenRecorderOperations();return operations.targets();}
    public static string[] capture_arguments(Settings target,int fps,bool cursor,int resolution=0)
    {using var operations=new ActorScreenRecorderOperations();return operations.capture_arguments(target,fps,cursor,resolution);}

    public Variant start(Settings options,Settings target)
    {
        if (_phase!=Phase.Idle) return "Screen capture is already changing state.";
        _request=_operations.prepare_start(this,options,target);
        if (_request["error"].AsString().Length>0) return _request["error"];
        _options=options.Duplicate(true);
        Variant audio=audio_recorder!=null ? audio_recorder.start() : Variant.From("");
        if (audio.VariantType==Variant.Type.Signal)
        {
            _phase=Phase.AudioStart;
            if (!ObserveAudio(audio,nameof(AudioStarted)))
            {
                _phase=Phase.Idle;_operations.cleanup(this);
                return "Could not wait for audio capture startup.";
            }
            return Variant.From(new Signal(this,SignalName.start_completed));
        }
        return BeginCapture(audio.AsString());
    }
    private Variant BeginCapture(string error)
    {
        _capture=_operations.begin_capture(this,_request,_options,error);
        if (_capture["error"].AsString().Length>0) return _capture["error"];
        _deadline=_capture["deadline"].AsUInt64();
        if (!_operations.startup_pending(this,_deadline))
            return _operations.complete_start(this,_capture["audio_started"].AsUInt64());
        _phase=Phase.CaptureStart;
        return Variant.From(new Signal(this,SignalName.start_completed));
    }

    public Variant stop()
    {
        if (_phase!=Phase.Idle) return "";
        _deadline=_operations.prepare_stop(this);
        if (_deadline==0) return "";
        if (!_operations.stop_pending(this,_deadline)) return FinishCapture();
        _phase=Phase.CaptureStop;
        return Variant.From(new Signal(this,SignalName.stop_completed));
    }
    private Variant FinishCapture()
    {
        _operations.finish_capture(this);
        Variant audio=audio_recorder!=null ? audio_recorder.stop() : default;
        if (audio.VariantType==Variant.Type.Signal)
        {
            _phase=Phase.AudioStop;
            if (!ObserveAudio(audio,nameof(AudioStopped)))
            {
                _phase=Phase.Idle;last_error="Could not wait for audio finalization.";_operations.cleanup(this);
                return "";
            }
            return Variant.From(new Signal(this,SignalName.stop_completed));
        }
        return BeginMux(audio);
    }
    private Variant BeginMux(Variant audio)
    {
        var stream=audio.VariantType==Variant.Type.Object ? audio.As<AudioStreamWav>() : null;
        _mux=_operations.prepare_mux(this,stream);
        if (_mux.Count>0)
        {
            if (_operations.mux_pending(_mux))
            {
                _phase=Phase.Mux;
                return Variant.From(new Signal(this,SignalName.stop_completed));
            }
            _operations.complete_mux(this,_mux);
        }
        _phase=Phase.Idle;
        return _operations.finish_stop(this);
    }

    public void _drain_errors() => _operations.drain_errors(this);
    public override void _Process(double delta)
    {
        _operations.drain_errors(this);
        Variant result;
        switch (_phase)
        {
            case Phase.CaptureStart:
                if (_operations.startup_pending(this,_deadline)) return;
                _phase=Phase.Idle;
                EmitSignal(SignalName.start_completed,_operations.complete_start(this,_capture["audio_started"].AsUInt64()));
                break;
            case Phase.CaptureStop:
                if (_operations.stop_pending(this,_deadline)) return;
                _phase=Phase.Idle;
                result=FinishCapture();
                if (result.VariantType!=Variant.Type.Signal) EmitSignal(SignalName.stop_completed,result);
                break;
            case Phase.Mux:
                if (_operations.mux_pending(_mux)) return;
                _phase=Phase.Idle;
                _operations.complete_mux(this,_mux);
                EmitSignal(SignalName.stop_completed,_operations.finish_stop(this));
                break;
        }
    }
    public void cleanup()
    {
        var pending=_phase;
        _phase=Phase.Idle;
        DisconnectAudioCompletion();
        _operations.cleanup(this);
        if (pending is Phase.AudioStart or Phase.CaptureStart) EmitSignal(SignalName.start_completed,"Screen capture was cancelled.");
        else if (pending!=Phase.Idle) EmitSignal(SignalName.stop_completed,"");
    }
    public override void _ExitTree() => cleanup();
}
