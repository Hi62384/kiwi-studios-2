using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingUiFileJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    private bool _running;
    private bool Current(Control workspace,RefCounted session)=>GodotObject.IsInstanceValid(this)&&IsInsideTree()&&GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree()&&workspace.Get("session").As<RefCounted>()==session;
    public void start(Control workspace,string kind,string id,int slot){if(_running)return;_running=true;_ = Run(workspace,kind,id,slot,GetTree());}
    private async Task Run(Control workspace,string kind,string id,int slot,SceneTree tree)
    {
        var session=workspace.Get("session").As<RefCounted>();try
        {
            bool material=kind=="material";if(material&&(!await ModuleLinkUi.Flush(this,session,tree)||!Current(workspace,session)))return;var property=new ActorProperty();property.Set("options",material?new Settings {["extensions"]=new[]{"tres","res","material"},["native_resource_types"]=new[]{"Material"},["accepted_object_types"]=new[]{"material","natural_material","shader_material"}}:new Settings {["extensions"]=new[]{"tres","res","glb","gltf","tscn","scn","obj"},["native_resource_types"]=new[]{"KiwiModelDocument","Mesh","PackedScene"}});var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","pick_file",workspace,new GArray {property,material?"Choose building material":"Choose reusable model"});var returned=await ToSignal(bridge,"completed");if(!Current(workspace,session)||returned.Length==0||returned[0].VariantType!=Variant.Type.String)return;string path=returned[0].AsString();if(path.Length==0||path=="::empty-resource::")return;
            if(material){var loaded=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("material",path).As<Material>();if(loaded==null)return;using var buildings=new BuildingSessionOperations();using var documents=new ModelDocumentOperations();var root=documents.component(session.Get("document").As<Resource>(),id);if(buildings.source(root)!=null)buildings.set_material(session,id,slot,loaded);}
            else{using var documents=new ModelDocumentOperations();var document=session.Get("document").As<Resource>();var target=documents.component(document,id);if(target==null)return;var canvas=workspace.Get("canvas").As<Control>();var pose=documents.world_transform(document,target).AffineInverse()*new Transform3D(Basis.Identity,canvas.Get("target").AsVector3());using var modules=new BuildingModuleOperations();var result=modules.insert(session,id,path,pose,workspace.Get("path").AsString());string error=result["error"].AsString();workspace.Get("status").As<Label>().Text=error.Length>0?error:"Model inserted";}
        }
        catch(Exception failure){GD.PushError(failure.ToString());if(GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree())workspace.Get("status").As<Label>().Text=failure.Message;}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
