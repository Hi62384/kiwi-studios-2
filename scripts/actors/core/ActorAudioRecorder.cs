using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorAudioRecorder : Node
{
    [Signal] public delegate void start_completedEventHandler(string error);
    [Signal] public delegate void stop_completedEventHandler(Variant stream);
    [Signal] public delegate void files_completedEventHandler(Settings result);
    public static Settings active_take_directories {get;} = new();
    public static Settings active_directories() => active_take_directories;
    public bool disk_backed {get;set;}
    public RefCounted? _mic_writer {get;set;}
    public RefCounted? _timeline_writer {get;set;}
    public string _take_directory {get;set;} = "";
    public string _capture_problem {get;set;} = "";
    public double _system_check_elapsed {get;set;}
    public AudioStreamPlayer? player {get;set;}
    public AudioEffectRecord? effect {get;set;}
    public string bus_name {get;set;} = "";
    public bool recording {get;set;}
    public Settings preferences_override {get;set;} = new();
    public AudioEffectCapture? capture {get;set;}
    public float[] peaks {get;set;} = System.Array.Empty<float>();
    public double _peak {get;set;}
    public int _peak_frames {get;set;}
    public bool _mono {get;set;}
    public WindowsSystemAudio? system_capture {get;set;}
    public float[] _system_peaks {get;set;} = System.Array.Empty<float>();
    public float[] _mic_peaks {get;set;} = System.Array.Empty<float>();
    public double _system_peak {get;set;}
    public int _system_frames {get;set;}
    public bool record_timeline {get;set;}
    public bool monitor_timeline {get;set;}
    public string timeline_bus_name {get;set;} = "";
    public AudioEffectRecord? timeline_effect {get;set;}
    public AudioEffectCapture? timeline_capture {get;set;}
    public float[] _timeline_peaks {get;set;} = System.Array.Empty<float>();
    public double _timeline_peak {get;set;}
    public int _timeline_frames {get;set;}

    private readonly ActorAudioRecorderOperations _operations = new();
    private enum Phase { Idle, Starting, Stopping, StoppingSystemFile, WaitingForWriters }
    private Phase _phase;
    private Settings _request = new();
    private Settings _systemResult = new();
    private AudioStreamWav? _microphoneResult;
    private bool _fileStopReturnsWave;
    private GodotObject? _systemCompletionOwner;
    private StringName _systemCompletionName="";
    private Callable _systemCompletionCallback;
    private bool ObserveSystem(Variant completion,StringName method)
    {
        DisconnectSystemCompletion();
        var signal=completion.AsSignal();
        if (!GodotObject.IsInstanceValid(signal.Owner)) return false;
        _systemCompletionOwner=signal.Owner;
        _systemCompletionName=signal.Name;
        _systemCompletionCallback=new Callable(this,method);
        if (_systemCompletionOwner.Connect(_systemCompletionName,_systemCompletionCallback,(uint)ConnectFlags.OneShot)==Error.Ok) return true;
        _systemCompletionOwner=null;return false;
    }
    private void DisconnectSystemCompletion()
    {
        var owner=_systemCompletionOwner;_systemCompletionOwner=null;
        if (GodotObject.IsInstanceValid(owner) && owner!.IsConnected(_systemCompletionName,_systemCompletionCallback))
            owner.Disconnect(_systemCompletionName,_systemCompletionCallback);
    }
    private void SystemStarted(string error)
    {
        if (_phase!=Phase.Starting) return;
        DisconnectSystemCompletion();_phase=Phase.Idle;
        EmitSignal(SignalName.start_completed,_operations.complete_start(this,_request["preferences"].AsGodotDictionary(),error,active_take_directories));
    }
    private void SystemStopped(Variant stream)
    {
        if (_phase!=Phase.Stopping) return;
        DisconnectSystemCompletion();
        EmitSignal(SignalName.stop_completed,FinishWave(stream));
    }
    private void SystemFileStopped(Settings result)
    {
        if (_phase!=Phase.StoppingSystemFile) return;
        DisconnectSystemCompletion();_systemResult=result;_phase=Phase.WaitingForWriters;
        if (!_operations.writers_busy(this)) EmitFinishedFiles();
    }
    private void EmitFinishedFiles()
    {
        bool returnsWave=_fileStopReturnsWave;
        var result=FinishFiles();
        EmitSignal(returnsWave ? SignalName.stop_completed : SignalName.files_completed,result);
    }


    public Settings requested_preferences() => _operations.requested_preferences(this);
    public static bool monitors_timeline(Settings preferences)
    {using var operations=new ActorAudioRecorderOperations();return operations.monitors_timeline(preferences);}
    public static bool backing_requested(Settings preferences)
    {using var operations=new ActorAudioRecorderOperations();return operations.backing_requested(preferences);}
    public static string preference_error(Settings preferences)
    {using var operations=new ActorAudioRecorderOperations();return operations.preference_error(preferences);}

    public virtual Variant start()
    {
        if (_phase != Phase.Idle) return "Audio capture is already changing state.";
        _request = _operations.prepare_start(this,active_take_directories);
        if (_request["done"].AsBool()) return _request["error"];
        Variant result = system_capture != null
            ? system_capture.start(disk_backed ? _take_directory.PathJoin("system.wav") : "") : Variant.From("");
        if (result.VariantType != Variant.Type.Signal)
            return _operations.complete_start(this,_request["preferences"].AsGodotDictionary(),result.AsString(),active_take_directories);
        _phase = Phase.Starting;
        if (!ObserveSystem(result,nameof(SystemStarted)))
        {_phase=Phase.Idle;_operations.cleanup(this,active_take_directories);return "Could not wait for system audio startup.";}
        return Variant.From(new Signal(this,SignalName.start_completed));
    }

    public virtual Variant stop()
    {
        if (!recording) return default;
        if (disk_backed) return BeginFileStop(true);
        _microphoneResult = _operations.prepare_stop(this);
        Variant result = system_capture != null ? system_capture.stop() : default;
        if (result.VariantType != Variant.Type.Signal)
            return FinishWave(result);
        _phase = Phase.Stopping;
        if (!ObserveSystem(result,nameof(SystemStopped)))
        {_phase=Phase.Idle;_microphoneResult=null;_operations.cleanup(this,active_take_directories);return default;}
        return Variant.From(new Signal(this,SignalName.stop_completed));
    }

    public virtual Variant stop_to_files() => BeginFileStop(false);
    private Variant BeginFileStop(bool returnsWave)
    {
        if (_phase!=Phase.Idle) return returnsWave ? default : Variant.From(new Settings{["error"]="Recording finalization is already in progress.",["paths"]=new Godot.Collections.Array<string>()});
        _fileStopReturnsWave = returnsWave;
        _request = _operations.prepare_stop_files(this);
        if (_request["done"].AsBool()) return returnsWave ? default : _request["result"];
        Variant result = system_capture != null
            ? system_capture.stop_to_file(_request["directory"].AsString().PathJoin("system.wav")) : Variant.From(new Settings());
        if (result.VariantType == Variant.Type.Signal)
        {
            _phase = Phase.StoppingSystemFile;
            if (!ObserveSystem(result,nameof(SystemFileStopped)))
            {
                _systemResult=new Settings{["error"]="Could not wait for system audio finalization.",["path"]=""};
                _phase=Phase.WaitingForWriters;
                if (!_operations.writers_busy(this)) return FinishFiles();
            }
        }
        else
        {
            _systemResult = result.AsGodotDictionary();
            if (!_operations.writers_busy(this)) return FinishFiles();
            _phase = Phase.WaitingForWriters;
        }
        return Variant.From(new Signal(this,returnsWave ? SignalName.stop_completed : SignalName.files_completed));
    }

    private Variant FinishWave(Variant system)
    {
        _phase = Phase.Idle;
        var microphone = _microphoneResult;
        _microphoneResult = null;
        var wave = system.VariantType == Variant.Type.Object ? system.As<AudioStreamWav>() : null;
        return Variant.From(_operations.complete_stop(this,microphone,wave,active_take_directories));
    }
    private Variant FinishFiles()
    {
        _phase = Phase.Idle;
        var result = _operations.complete_stop_files(this,_request["directory"].AsString(),_systemResult,active_take_directories);
        return _fileStopReturnsWave ? default : Variant.From(result);
    }

    public override void _Process(double delta)
    {
        _operations.process(this,delta);
        if (_phase==Phase.WaitingForWriters && !_operations.writers_busy(this)) EmitFinishedFiles();
    }

    public string capture_error() => _operations.capture_error(this);
    public void _drain_to_writer(AudioEffectCapture? input,RefCounted? writer) => _operations.drain_to_writer(input,writer);
    public static void convert_to_mono(AudioStreamWav stream)
    {using var operations=new ActorAudioRecorderOperations();operations.convert_to_mono(stream);}
    public static AudioStreamWav? mix_streams(AudioStreamWav? mic,AudioStreamWav? system)
    {using var operations=new ActorAudioRecorderOperations();return operations.mix_streams(mic,system);}
    public static Vector2 _sample(AudioStreamWav stream,double time)
    {using var operations=new ActorAudioRecorderOperations();return operations.sample(stream,time);}
    public static Vector2 _sample_data(byte[] data,int rate,bool stereo,double time)
    {using var operations=new ActorAudioRecorderOperations();return operations.sample_data(data,rate,stereo,time);}
    public void _cleanup()
    {
        var pending=_phase;
        _phase=Phase.Idle;
        _microphoneResult=null;
        DisconnectSystemCompletion();
        _operations.cleanup(this,active_take_directories);
        if (pending==Phase.Starting) EmitSignal(SignalName.start_completed,"Audio capture was cancelled.");
        else if (pending==Phase.Stopping || pending!=Phase.Idle && _fileStopReturnsWave) EmitSignal(SignalName.stop_completed,default(Variant));
        else if (pending!=Phase.Idle) EmitSignal(SignalName.files_completed,new Settings{["error"]="Audio capture was cancelled.",["paths"]=new Godot.Collections.Array<string>()});
    }
    public override void _ExitTree()
    {
        effect?.SetRecordingActive(false);
        _cleanup();
    }
}
