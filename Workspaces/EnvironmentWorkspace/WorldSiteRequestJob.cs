using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSiteRequestJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    private bool _running;
    private static bool Current(Control owner,RefCounted session)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&owner.Get("session").As<RefCounted>()==session;
    private static void Status(Control owner,string text)=>owner.Get("status").As<Label>().Text=text;
    private async Task<Variant> Legacy(Control owner,string kind,GArray arguments)
    {var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run",kind,owner,arguments);var result=await ToSignal(bridge,"completed");return result.Length>0?result[0]:default;}
    public void start(Control owner,string id,int index,string profile){if(_running)return;_running=true;_ = Run(owner,id,index,profile,GetTree());}
    private async Task Run(Control owner,string id,int index,string profile,SceneTree tree)
    {
        var session=owner.Get("session").As<RefCounted>();WorldSiteJob? pending=null;Callable cancellation=default;try
        {
            var edits=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd");string selectedId="";if(index>=0){var current=edits.Call("source",session,id).As<Resource>();if(current==null||index>=current.Get("settlements").AsGodotArray().Count)return;selectedId=current.Get("settlements").AsGodotArray()[index].AsGodotDictionary()["id"].AsString();}
            var flushed=await Legacy(owner,"world_flush",new GArray {session});if(!Current(owner,session)||flushed.VariantType!=Variant.Type.Bool||!flushed.AsBool())return;var authored=edits.Call("source",session,id).As<Resource>();if(authored==null)return;authored=authored.Call("copy").As<Resource>();
            if(profile.Length>0){authored=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd").Call("create",authored,Vector3.Zero,profile).As<Resource>();var settlements=authored.Get("settlements").AsGodotArray();index=settlements.Count-1;var settlement=settlements[index].AsGodotDictionary();var dimensions=authored.Get("dimensions").AsVector2();settlement["radius"]=Math.Min(settlement["radius"].AsDouble(),Math.Max(8,Math.Min(dimensions.X,dimensions.Y)*.12));}
            else{index=-1;var settlements=authored.Get("settlements").AsGodotArray();for(int candidate=0;candidate<settlements.Count;candidate++)if(settlements[candidate].AsGodotDictionary()["id"].AsString()==selectedId){index=candidate;break;}}if(index<0)return;
            var captured=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").Call("capture",session,id,authored).AsGodotDictionary();string error=captured["error"].AsString();if(error.Length>0){Status(owner,error);return;}authored.Set("terrain_field",captured["field"]);using var occupancy=new WorldPlacementOperations();error=occupancy.capture(session,id,authored);if(error.Length>0){Status(owner,error);return;}if(session.Call("_pending_source_valid").AsBool()){Status(owner,"Finish the current source edit before finding a settlement site.");return;}
            long revision=session.Get("revision").AsInt64();var document=session.Get("document").As<Resource>();var job=new WorldSiteJob();pending=job;owner.SetMeta("world_site_job",job);var cancel=new Callable(job,"cancel");cancellation=cancel;session.Set("pending_source_cancel",cancel);Status(owner,"Finding a settlement site…");job.start(authored,index);while(!job.complete()){if(!Current(owner,session)||session.Get("document").As<Resource>()!=document||session.Get("revision").AsInt64()!=revision)job.cancel();await ToSignal(tree,SceneTree.SignalName.ProcessFrame);}var result=job.collect();if(session.Get("pending_source_cancel").AsCallable().Equals(cancel))session.Set("pending_source_cancel",default(Callable));if(!GodotObject.IsInstanceValid(owner))return;if(owner.HasMeta("world_site_job")&&owner.GetMeta("world_site_job").As<RefCounted>()==job)owner.RemoveMeta("world_site_job");if(!Current(owner,session)||session.Get("document").As<Resource>()!=document||session.Get("revision").AsInt64()!=revision||job.cancelled())return;error=result.TryGetValue("error",out var message)?message.AsString():"";if(error.Length>0){Status(owner,error);return;}
            authored.Get("settlements").AsGodotArray()[index].AsGodotDictionary()["center"]=result["position"];owner.SetMeta("world_section",2);owner.SetMeta("world_settlement_index",index);var returned=await Legacy(owner,"world_edit",new GArray {session,id,authored,"Place settlement on suitable terrain"});if(Current(owner,session)&&returned.VariantType==Variant.Type.Dictionary){var errors=returned.AsGodotDictionary()["errors"].AsStringArray();Status(owner,errors.Length>0?errors[0]:"Settlement placed");}
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{if(pending!=null){if(pending.task_id>=0){pending.cancel();pending.collect();}if(session.Get("pending_source_cancel").AsCallable().Equals(cancellation))session.Set("pending_source_cancel",default(Callable));if(GodotObject.IsInstanceValid(owner)&&owner.HasMeta("world_site_job")&&owner.GetMeta("world_site_job").As<RefCounted>()==pending)owner.RemoveMeta("world_site_job");}finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
