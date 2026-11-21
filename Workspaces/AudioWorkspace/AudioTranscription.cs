using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioTranscription : RefCounted
{
    public static Settings parse(Variant data,double duration)
    {using var operations=new AudioTranscriptionOperations();return operations.parse(data,duration);}
    public static Settings run(RefCounted document,string id,string executable,string model,RefCounted? job=null)
    {using var operations=new AudioTranscriptionOperations();return operations.run(document,id,executable,model,job);}
    public static string apply(RefCounted session,string id,Settings result,string text,bool markers)
    {using var operations=new AudioTranscriptionOperations();return operations.apply(session,id,result,text,markers);}
}
