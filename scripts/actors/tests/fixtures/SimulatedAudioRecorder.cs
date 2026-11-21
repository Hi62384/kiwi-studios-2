using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class SimulatedAudioRecorder : ActorAudioRecorder
{
    [Signal] public delegate void simulated_stop_completedEventHandler(Variant stream);
    [Signal] public delegate void simulated_files_completedEventHandler(Settings result);
    public AudioStreamWav? recorded {get;set;}
    public int starts {get;set;}
    public override void _Process(double delta) { }
    public override Variant start() {starts++;recording=true;return "";}
    public override Variant stop()
    {
        recording=false;
        GetTree().CreateTimer(.03).Connect(SceneTreeTimer.SignalName.Timeout,new Callable(this,nameof(FinishStop)),(uint)ConnectFlags.OneShot);
        return Variant.From(new Signal(this,SignalName.simulated_stop_completed));
    }
    private void FinishStop()=>EmitSignal(SignalName.simulated_stop_completed,Variant.From(recorded));
    public override Variant stop_to_files()
    {
        recording=false;
        GetTree().CreateTimer(.03).Connect(SceneTreeTimer.SignalName.Timeout,new Callable(this,nameof(FinishFiles)),(uint)ConnectFlags.OneShot);
        return Variant.From(new Signal(this,SignalName.simulated_files_completed));
    }
    private void FinishFiles()
    {
        string directory=ProjectSettings.GlobalizePath("user://audio_workspace/takes/"+ActorData.new_id());
        DirAccess.MakeDirRecursiveAbsolute(directory);
        string path=directory.PathJoin("microphone.wav");
        recorded!.SaveToWav(path);
        EmitSignal(SignalName.simulated_files_completed,new Settings{["directory"]=directory,["paths"]=new Godot.Collections.Array<string>{path},["mono"]=false,["error"]=""});
    }
}
