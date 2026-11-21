using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TransformationWorkspaceJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    public int result=(int)Error.Ok;
    private static readonly string BridgePath="res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd";
    private void Done(){if(finished)return;finished=true;if(GodotObject.IsInstanceValid(this))EmitSignal(SignalName.completed);}
    public override void _ExitTree()=>Done();
    private static bool Current(Control owner,RefCounted session)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&!owner.IsQueuedForDeletion()&&owner.Get("session").As<RefCounted>()==session;
    private static void Status(Control owner,string message)=>owner.Get("status").As<Label>().Text=message;
    public void start(Control owner,string kind,string path){_ = Run(owner,kind,path);}
    private async Task<Variant> Pick(Control owner,string kind,GArray arguments){var bridge=GD.Load<GDScript>(BridgePath).New().As<Node>();AddChild(bridge);var waiting=ToSignal(bridge,"completed");bridge.Call("run",kind,owner,arguments);var returned=await waiting;return returned.Length>0?returned[0]:default;}
    private async Task Run(Control owner,string kind,string path)
    {
        var session=owner.Get("session").As<RefCounted>();Node? capture=null;try
        {
            using var operations=new TransformationWorkspaceOperations();using var resources=new TransformationResourceOperations();if(kind=="tool"){operations.finish_pending(owner);operations.edit_mode(owner);var canvas=owner.Get("canvas").As<Control>();canvas.Set("tool",path);canvas.Set("pixel_mode","brush");canvas.Set("paint_new_layer",false);owner.Set("_ui_pending",true);canvas.GrabFocus();if(path=="pixel_select"){var bridge=GD.Load<GDScript>(BridgePath).New().As<Node>();AddChild(bridge);var waiting=ToSignal(bridge,"completed");bridge.Call("run","flatten_image",owner,new GArray {owner.Get("edit_renderer")});var returned=await waiting;if(!Current(owner,session)||returned.Length==0)return;canvas.Set("pixel_source",returned[0]);canvas.Set("pixel_domain",new Rect2I(Vector2I.Zero,session.Get("document").AsGodotObject().Get("canvas_size").AsVector2I()));}return;}
            if(kind=="merge")
            {
                operations.finish_pending(owner);var chosen=session.Get("selected").AsGodotArray();if(chosen.Count<2){Status(owner,"Choose at least two adjacent components to merge at the playhead.");return;}long revision=session.Get("revision").AsInt64();double at=session.Get("playhead").AsDouble();var ids=new string[chosen.Count];for(int index=0;index<ids.Length;index++)ids[index]=chosen[index].AsString();var snapshot=GD.Load<GDScript>("res://Workspaces/TransformationWorkspace/transformation_session.gd").New().As<RefCounted>();var document=resources.snapshot(session.Get("document").As<Resource>());snapshot.Set("document",document);foreach(var raw in document.Get("components").AsGodotArray()){var item=raw.As<Resource>();item.Set("visible",item.Get("visible").AsBool()&&Array.IndexOf(ids,item.Get("id").AsString())>=0);}capture=GD.Load<GDScript>("res://Workspaces/TransformationWorkspace/transformation_renderer.gd").New().As<Node>();owner.AddChild(capture);capture.Call("sync",snapshot,at,new Settings());Status(owner,"Preparing the selected components for a non-destructive merge…");ulong began=Time.GetTicksMsec();bool ready=false;while(Time.GetTicksMsec()-began<15000){await ToSignal(owner.GetTree(),SceneTree.SignalName.ProcessFrame);if(!Current(owner,session))return;capture.Call("sync",snapshot,at,new Settings());var cache=capture.Get("cache").AsGodotObject();ready=cache.Get("worker").AsGodotObject()==null&&cache.Get("requests").AsGodotArray().Count==0;if(ready)break;}if(!ready){Status(owner,"Merge preparation timed out; original components are unchanged.");return;}using var renderer=new TransformationRendererOperations();var flattened=renderer.flatten(capture);if(!flattened.finished)await ToSignal(flattened,"completed");using var image=flattened.result;if(!Current(owner,session))return;if(revision!=session.Get("revision").AsInt64()){Status(owner,"Merge canceled because the document changed.");return;}using var events=new TransformationComponentEvents();string message=events.merge(session,ids,image,at);if(message.Length>0)Status(owner,message);else{operations.seek(owner,at);Status(owner,"Merged snapshot starts here. Earlier source animation remains editable and can be scrubbed backward.");}return;
            }
            if(kind is "import" or "open")
            {
                var state=session.Call("active_state",default(Variant)).As<Resource>();var property=new ActorProperty();property.Set("options",kind=="open"?new Settings {["extensions"]=new[]{"tres","res"},["native_resource_types"]=new[]{"KiwiTransformationImage2D"}}:new Settings {["extensions"]=new[]{"png","jpg","jpeg","webp","bmp","svg","tga"},["raw_extensions"]=new[]{"png","jpg","jpeg","webp","bmp","svg","tga"}});var value=await Pick(owner,"pick_file",new GArray {property,kind=="open"?"Open Transformation Image 2D":"Load artwork for this state"});if(!Current(owner,session)||value.VariantType!=Variant.Type.String)return;string selected=value.AsString();if(selected.Length==0||selected=="::empty-resource::")return;if(kind=="import"){if(state==session.Call("active_state",default(Variant)).As<Resource>())operations.import_image(owner,selected);}else{var tabs=owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs");if(tabs!=null)tabs.Call("open_transformation",selected);else operations.open_source(owner,selected,new Settings());}return;
            }
            if(kind=="save_as"||(kind=="save"&&path.Length==0))
            {
                string current=owner.Get("path").AsString();var provider=Callable.From<Resource>(()=>{operations.finish_pending(owner);return resources.snapshot(owner.Get("session").AsGodotObject().Get("document").As<Resource>());});var picked=await Pick(owner,"resource_save",new GArray {"Save editable Transformation Image 2D",current.Length>0?current.GetFile().GetBaseName():"Transformation Image","tres",new[]{"tres","res"},provider});if(!Current(owner,session)||picked.VariantType!=Variant.Type.Dictionary)return;var response=picked.AsGodotDictionary();if(!response.TryGetValue("cancelled",out var cancelled)||cancelled.AsBool())return;path=response["path"].AsString();
            }
            operations.finish_pending(owner);var original=session.Get("document").As<Resource>();var errors=resources.validate(original);if(errors.Length>0){Status(owner,errors[0]);result=(int)Error.InvalidData;return;}long savedRevision=session.Get("revision").AsInt64();var saved=resources.snapshot(original);saved.Set("workspace_state",operations.ui_state(owner));if(DisplayServer.GetName()!="headless"){await ToSignal(Engine.GetSingleton("RenderingServer"),RenderingServer.SignalName.FramePostDraw);if(Current(owner,session)){var texture=owner.Get("canvas").AsGodotObject().Get("preview").As<Texture2D>();using var image=texture?.GetImage();if(image!=null){double scale=Math.Min(192.0/image.GetWidth(),144.0/image.GetHeight());image.Resize(Math.Max(1,(int)Math.Round(image.GetWidth()*scale,MidpointRounding.AwayFromZero)),Math.Max(1,(int)Math.Round(image.GetHeight()*scale,MidpointRounding.AwayFromZero)),Image.Interpolation.Bilinear);saved.Set("preview_png",image.SavePngToBuffer());}}}var error=ResourceSaver.Save(saved,path);result=(int)error;if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree())return;if(error!=Error.Ok){Status(owner,"Save failed ("+(int)error+").");return;}if(Current(owner,session)){owner.Set("path",path);original.Set("workspace_state",saved.Get("workspace_state"));original.Set("preview_png",saved.Get("preview_png"));}session.Set("dirty",session.Get("revision").AsInt64()!=savedRevision);owner.EmitSignal("asset_saved",path,session);GD.Load<GDScript>(BridgePath).Call("refresh_filesystem");owner.Get("header").As<Label>().Text="TRANSFORMATION 2D / "+owner.Get("path").AsString().GetFile();Status(owner,"Saved editable states and animation · "+path);
        }
        catch(Exception error){result=(int)Error.Failed;GD.PushError(error.ToString());}
        finally{if(GodotObject.IsInstanceValid(capture))capture!.QueueFree();Done();if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
public partial class TransformationWorkspaceOperations
{
    public TransformationWorkspaceJob job(Control owner,string kind,string path){var job=new TransformationWorkspaceJob();owner.AddChild(job);job.start(owner,kind,path);return job;}
}
