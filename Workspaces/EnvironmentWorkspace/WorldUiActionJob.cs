using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldUiActionJob : Node
{
    private bool _running;
    public void start(Control owner,string kind,string id,Variant value,string label){if(_running)return;_running=true;_ = Run(owner,kind,id,value,label);}
    private static bool Current(Control owner,RefCounted session)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&WorldUiOperations.Session(owner)==session;
    private async Task<Variant> Bridge(Control owner,string method,GArray arguments)
    {var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);var waiting=ToSignal(bridge,"completed");if(method=="edit")bridge.Call("world_edit_now",arguments[0],arguments[1],arguments[2],arguments[3]);else if(method=="flush")bridge.Call("world_flush_now",arguments[0]);else bridge.Call("run","pick_file",owner,arguments);var values=await waiting;return values.Length>0?values[0]:default;}
    private async Task Run(Control owner,string kind,string id,Variant value,string label)
    {
        var session=WorldUiOperations.Session(owner);try
        {
            if(kind=="apply")
            {var returned=await Bridge(owner,"edit",new GArray {session,id,value,label});if(!Current(owner,session)||returned.VariantType!=Variant.Type.Dictionary)return;var result=returned.AsGodotDictionary();if(result.TryGetValue("cancelled",out var cancelled)&&cancelled.AsBool())return;var errors=result["errors"].AsStringArray();var warnings=result["warnings"].AsStringArray();owner.Get("status").As<Label>().Text=errors.Length>0?errors[0]:warnings.Length>0?string.Join(" · ",warnings):"World updated";return;}
            if(kind=="grade")
            {var flushed=await Bridge(owner,"flush",new GArray {session});if(!Current(owner,session)||flushed.VariantType!=Variant.Type.Bool||!flushed.AsBool())return;var root=session.Get("document").As<Resource>().Call("component",id).As<Resource>();if(root==null)return;var source=new WorldSessionOperations().source(root);if(source==null)return;var result=new WorldTerrainOperations().grading_plan(session,id,source,value.AsBool());string error=result["error"].AsString();if(error.Length>0)owner.Get("status").As<Label>().Text=error;else owner.Call("_regenerate_terrain",result["id"].AsString(),result["settings"]);return;}
            var property=new ActorProperty();property.Set("options",new Settings {["extensions"]=new[]{"tres","res","mesh","glb","gltf","obj"},["raw_extensions"]=new[]{"glb","gltf","obj"},["native_resource_types"]=new[]{"KiwiModelDocument","Mesh","PackedScene"}});var selected=await Bridge(owner,"pick",new GArray {property,"Choose a reusable placement model"});if(!Current(owner,session)||selected.VariantType!=Variant.Type.String)return;string path=selected.AsString();if(path.Length==0||path=="::empty-resource::"||session.Get("document").As<Resource>().Call("component",id).AsGodotObject()==null)return;var loaded=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("load_parts",path).AsGodotDictionary();string loadError=loaded["error"].AsString();if(loadError.Length>0){owner.Get("status").As<Label>().Text=loadError;return;}var current=WorldUiOperations.Source(owner,id);if(current==null)return;var next=new WorldPropOperations().create(current,path,value.AsString());owner.SetMeta("world_section",5);owner.SetMeta("world_prop_index",next.Get("prop_rules").AsGodotArray().Count-1);new WorldUiOperations().apply(owner,id,next,"Populate world objects");
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
