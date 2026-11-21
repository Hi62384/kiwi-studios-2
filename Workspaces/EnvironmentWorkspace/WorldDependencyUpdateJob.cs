using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldDependencyUpdateJob : Node
{
    private bool _running;
    private static bool Current(Control owner,RefCounted session)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&owner.Get("session").As<RefCounted>()==session;
    public void start(Control owner,RefCounted session,string id,Resource desired,long key){if(_running)return;_running=true;_ = Run(owner,session,id,desired,key);}
    private async Task Run(Control owner,RefCounted session,string id,Resource desired,long key)
    {
        try
        {
            long revision=session.Get("revision").AsInt64();var undo=session.Get("_undo").AsGodotArray();var previous=undo.Count>0?undo[^1].AsGodotDictionary():new Settings();var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","world_edit",owner,new GArray {session,id,desired,"Refresh dependent world"});var returned=await ToSignal(bridge,"completed");if(!Current(owner,session)||returned.Length==0||returned[0].VariantType!=Variant.Type.Dictionary)return;undo=session.Get("_undo").AsGodotArray();var result=returned[0].AsGodotDictionary();if(result.TryGetValue("cancelled",out var cancelled)&&cancelled.AsBool())return;using var operations=new WorldDependencyOperations();var errors=result["errors"].AsStringArray();if(errors.Length>0){operations.state(owner)["failed"].AsGodotDictionary()[id]=key;owner.Get("status").As<Label>().Text=errors[0];return;}if(session.Get("revision").AsInt64()!=revision+1||previous.Count==0||undo.Count==0)return;var generated=undo[^1].AsGodotDictionary();if(generated.TryGetValue("label",out var label)&&label.AsString()!="Refresh dependent world"||!generated.ContainsKey("label"))return;
            if(previous.TryGetValue("custom",out var custom)&&custom.AsBool())
            {var before=generated["before"].AsGodotDictionary();var after=generated["after"].AsGodotDictionary();var callbacks=new Settings {["undo"]=previous["undo"],["redo"]=previous["redo"]};var history=new WorldDependencyHistory {session=session,before=before,after=after,callbacks=callbacks};previous["undo"]=Callable.From(history.undo);previous["redo"]=Callable.From(history.redo);previous["cost"]=(previous.TryGetValue("cost",out var cost)?cost.AsInt64():0L)+operations.cost(before)+operations.cost(after);}
            else previous["after"]=generated["after"];undo.RemoveAt(undo.Count-1);if(undo.Count==0||!WorldDependencyOperations.SameEntry(undo[^1],previous))undo.Add(previous);
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
