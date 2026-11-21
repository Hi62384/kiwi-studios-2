using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWorkspaceComponentJob : Node
{
    private bool _running;
    private bool Current(Control owner,RefCounted session)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&owner.Get("session").As<RefCounted>()==session;
    private static void Status(Control owner,string text)=>owner.Get("status").As<Label>().Text=text;
    public void start(Control owner,string kind,string id){if(_running)return;_running=true;_ = Run(owner,kind,id);}
    private async Task Run(Control owner,string kind,string id)
    {
        var session=owner.Get("session").As<RefCounted>();TerrainBakeState? baking=null;Resource? output=null;
        try
        {
            string title,suggested,extension;string[] formats;var canvas=owner.Get("canvas").As<Control>();
            if(kind=="bake")
            {
                if(owner.Get("_terrain_bake").As<RefCounted>()!=null)return;if(owner.Get("_generation_jobs").AsGodotArray().Count>0){Status(owner,"Finish generation before baking terrain.");return;}canvas.Call("cancel_all");canvas.Call("sync");baking=new TerrainBakeState();owner.Set("_terrain_bake",baking);var job=new TerrainBakeJob();owner.AddChild(job);job.start(baking,canvas.Get("renderer").As<Node3D>(),id,owner,false);var result=await ToSignal(job,"completed");if(GodotObject.IsInstanceValid(owner)&&owner.Get("_terrain_bake").As<RefCounted>()==baking)owner.Set("_terrain_bake",default(Variant));if(!Current(owner,session))return;output=result.Length>0?result[0].As<Resource>():null;if(output==null){Status(owner,baking.cancelled?"Terrain bake canceled.":baking.error);return;}title="Save editable terrain model";suggested="Terrain model";extension="res";formats=new[]{"res","tres"};
            }
            else
            {
                var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","flush",owner,new GArray());var result=await ToSignal(bridge,"completed");if(!Current(owner,session)||result.Length==0||!result[0].AsBool())return;using var environments=new EnvironmentSessionOperations();output=environments.selected_environment(session);var primary=session.Call("primary").As<Resource>();
                if(primary!=null&&session.Get("selected").AsGodotArray().Count==1)
                {
                    using var natural=new ModelNaturalSettings();using var clusters=new ModelNaturalCluster();using var architectural=new ArchitecturalComponentOperations();using var buildings=new BuildingSessionOperations();string generator=primary.Get("generator").AsString();
                    if(natural.accepts(generator)||clusters.accepts(primary)||architectural.accepts(generator)||buildings.source(primary)!=null)
                    {
                        output?.Dispose();output=new KiwiModelDocument();using var documents=new ModelDocumentOperations();using var components=new ModelComponentOperations();var document=session.Get("document").As<Resource>();string primaryId=primary.Get("id").AsString();foreach(var value in document.Get("components").AsGodotArray()){var item=value.As<Resource>();string componentId=item.Get("id").AsString();if(componentId!=primaryId&&!documents.is_descendant(document,componentId,primaryId))continue;var copy=components.copy_component(item,false);if(componentId==primaryId){copy.Set("parent_id","");copy.Set("transform",Transform3D.Identity);}output.Get("components").AsGodotArray().Add(copy);}
                    }
                }
                if(output==null){Status(owner,"Select components to save.");return;}title="Save reusable component";suggested=primary?.Get("title").AsString()??"Environment component";extension="tres";formats=new[]{"tres","res"};
            }
            var saveBridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(saveBridge);var saved=output;saveBridge.Call("run","resource_save",owner,new GArray {title,suggested,extension,formats,Callable.From(()=>saved)});var picked=await ToSignal(saveBridge,"completed");if(!Current(owner,session)||picked.Length==0||picked[0].VariantType!=Variant.Type.Dictionary)return;var choice=picked[0].AsGodotDictionary();if(!choice.TryGetValue("cancelled",out var cancelled)||cancelled.AsBool())return;string destination=choice["path"].AsString();var error=ResourceSaver.Save(output,destination,kind=="bake"&&destination.GetExtension().ToLowerInvariant()=="res"?ResourceSaver.SaverFlags.Compress:0);
            Status(owner,kind=="bake"?(error==Error.Ok?"Saved editable terrain model":"Could not save terrain model."):(error==Error.Ok?"Saved reusable component":"Could not save component"));if(error==Error.Ok){if(kind!="bake")owner.Get("library").As<EnvironmentLibrary>().scan();GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").Call("refresh_filesystem");}
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{if(baking!=null&&GodotObject.IsInstanceValid(owner)&&owner.Get("_terrain_bake").As<RefCounted>()==baking)owner.Set("_terrain_bake",default(Variant));output?.Dispose();baking?.Dispose();if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
