using Godot;
using System.Collections.Generic;
using System.Threading;

public partial class ShaderPreviewLogger : Logger
{
    private readonly object _gate=new();
    private readonly List<string> _messages=new();
    private bool _capturing;
    public bool capturing {get=>Volatile.Read(ref _capturing);set=>Volatile.Write(ref _capturing,value);}
    public void clear(){lock(_gate)_messages.Clear();}
    public string[] messages(){lock(_gate)return _messages.ToArray();}
    public override void _LogError(string function,string file,int line,string code,string rationale,bool editorNotify,int errorType,Godot.Collections.Array<ScriptBacktrace> scriptBacktraces)
    {
        // Logging from this callback would recurse into the logger itself.
        if(!capturing||errorType!=(int)ErrorType.Shader)return;
        lock(_gate)_messages.Add("Line "+line+": "+(rationale.Length>0?rationale:code));
    }
}
