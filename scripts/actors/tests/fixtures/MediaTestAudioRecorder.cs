using Godot;
[GlobalClass]
public partial class MediaTestAudioRecorder : ActorAudioRecorder
{
    public AudioStreamWav? output {get;set;}
    public override Variant stop() {recording=false;return Variant.From(output);}
}
