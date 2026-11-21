using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingUiApplyJob : Node
{
    [Signal] public delegate void completedEventHandler();
    private bool _running;
    public bool finished {get;private set;}
    private static BuildingEditOperations Edits()=>Engine.GetSingleton("KiwiNativeServices").Call("service","building_edit").As<BuildingEditOperations>();
    public void start(Control workspace,string id,Resource source,string label){if(_running)return;_running=true;_ = Run(workspace,id,source,label,GetTree());}
    private async Task Run(Control workspace,string id,Resource source,string label,SceneTree tree)
    {
        var session=workspace.Get("session").As<RefCounted>();try
        {
            workspace.Get("status").As<Label>().Text="Updating building…";var state=Edits().start(session,id,source,label);Settings result;if(state.TryGetValue("result",out var immediate))result=immediate.AsGodotDictionary();else{while(!Edits().poll(session,state))await ToSignal(tree,SceneTree.SignalName.ProcessFrame);result=Edits().finish(session,state);}if(!GodotObject.IsInstanceValid(workspace)||workspace.Get("session").As<RefCounted>()!=session||(result.TryGetValue("cancelled",out var cancelled)&&cancelled.AsBool()))return;var errors=result["errors"].AsStringArray();var warnings=result["warnings"].AsStringArray();workspace.Get("status").As<Label>().Text=errors.Length>0?errors[0]:warnings.Length>0?string.Join(" · ",warnings):"Building updated";
        }
        catch(Exception failure){GD.PushError(failure.ToString());if(GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree())workspace.Get("status").As<Label>().Text=failure.Message;}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
