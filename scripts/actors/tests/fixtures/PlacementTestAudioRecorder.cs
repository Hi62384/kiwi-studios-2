using Godot;
[GlobalClass]
public partial class PlacementTestAudioRecorder : ActorAudioRecorder
{
    public AudioStreamWav? output {get;set;}
    public override Variant start() {recording=true;peaks=new float[]{.2f,.5f,.7f};return "";}
    public override Variant stop() {recording=false;return Variant.From(output);}
}
