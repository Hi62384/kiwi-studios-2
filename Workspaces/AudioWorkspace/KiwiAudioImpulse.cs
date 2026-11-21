using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class KiwiAudioImpulse : RefCounted
{
    public static double duration(string type,Settings parameters)
    { using var operations=new AudioImpulseOperations(); return operations.duration(type,parameters); }
    public static AudioStreamWav? generate(string type,Settings parameters,int rate,RefCounted? job=null)
    { using var operations=new AudioImpulseOperations(); return operations.generate(type,parameters,rate,job); }
}
