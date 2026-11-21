using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioOptionalProcess : RefCounted
{
    public static Settings run(string executable,string[] args,string input="",RefCounted? job=null,double seconds=60,int max_bytes=2097152)
    {using var operations=new AudioOptionalProcessOperations();return operations.run(executable,args,input,job,seconds,max_bytes);}
}
