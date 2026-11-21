using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentWorkspaceSaveJob
{
    public void start_mode(Control owner,string mode)
    {if(_running)return;_running=true;_owner=owner;_session=owner.Get("session").As<RefCounted>();_ = RunSelected(mode,GetTree());}
    private async Task RunSelected(string mode,SceneTree tree)
    {
        try
        {
            string destination=_owner!.Get("path").AsString();if(mode=="save_as"||destination.Length==0)
            {
                var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);var session=_session!;bridge.Call("run","resource_save",_owner,new Godot.Collections.Array {"Save environment",destination.Length>0?destination.GetFile().GetBaseName():"Environment","tres",new[]{"tres","res"},Callable.From(()=>session.Get("document").As<Resource>().Call("snapshot"))});var returned=await ToSignal(bridge,"completed");if(!Current()||returned.Length==0||returned[0].VariantType!=Variant.Type.Dictionary){result=Error.Skip;return;}var choice=returned[0].AsGodotDictionary();if(!choice.TryGetValue("cancelled",out var cancelled)||cancelled.AsBool()){result=Error.Skip;return;}destination=choice["path"].AsString();
            }
            result=await Save(destination,tree);if(mode=="to_scene"&&result==Error.Ok&&Current()&&_owner!.Get("path").AsString().Length>0)_owner.EmitSignal("use_in_scene",_owner.Get("path"));
        }
        catch(Exception failure){GD.PushError(failure.ToString());Status("Could not save the environment.");result=Error.Failed;}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
