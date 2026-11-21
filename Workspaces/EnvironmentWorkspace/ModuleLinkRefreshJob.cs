using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class ModuleLinkRefreshJob : Node
{
    [Signal] public delegate void completedEventHandler();
    private readonly ModuleLinkOperations _links=new();
    private bool _running;
    public bool finished {get;private set;}
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private bool Live(Node tabs)=>GodotObject.IsInstanceValid(this)&&IsInsideTree()&&!IsQueuedForDeletion()&&GodotObject.IsInstanceValid(tabs)&&tabs.IsInsideTree()&&!tabs.IsQueuedForDeletion();
    public void start(Node tabs,string path){if(_running)return;_running=true;_ = Run(tabs,path,GetTree());}
    private async Task Run(Node tabs,string path,SceneTree tree)
    {
        try
        {
            var seen=new HashSet<ulong>();foreach(var value in tabs.Get("documents").AsGodotArray().Duplicate())
            {
                if(!Live(tabs))return;var record=value.AsGodotDictionary();string kind=Get(record,"type", "").AsString();if(kind is not ("model" or "environment"))continue;var state=Get(record,"state",new Settings()).AsGodotDictionary();var session=Get(state,"session").As<RefCounted>();var documents=tabs.Get("documents").AsGodotArray();int active=tabs.Get("_active_index").AsInt32();if(active>=0&&active<documents.Count&&record.RecursiveEqual(documents[active].AsGodotDictionary()))session=tabs.Get(kind=="model"?"model_workspace":"environment_workspace").As<Control>().Get("session").As<RefCounted>();if(session==null||!seen.Add(session.GetInstanceId()))continue;if(!await ModuleLinkUi.Flush(this,session,tree)||!Live(tabs))continue;string error=_links.refresh_changed(session,path);if(error.Length==0)continue;var workspace=tabs.Get(kind=="model"?"model_workspace":"environment_workspace").As<Control>();if(workspace.Get("session").As<RefCounted>()==session)workspace.Get("status").As<Label>().Text=error;
            }
        }
        catch(Exception failure){GD.PushError(failure.ToString());}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
