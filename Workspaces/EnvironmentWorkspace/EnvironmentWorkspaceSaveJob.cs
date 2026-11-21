using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

/// <summary>Waits for authored edits and generated preview data before atomically saving a snapshot.</summary>
public partial class EnvironmentWorkspaceSaveJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    public Error result {get;private set;}=Error.Busy;
    private bool _running;
    private Control? _owner;
    private RefCounted? _session;
    private readonly EnvironmentDocumentOperations _documents=new();
    private readonly TerrainDataOperations _terrain=new();
    private bool Current()=>GodotObject.IsInstanceValid(_owner)&&_owner!.IsInsideTree()&&_owner.Get("session").As<RefCounted>()==_session;
    private bool Live()=>GodotObject.IsInstanceValid(_owner)&&_owner!.IsInsideTree();
    private static bool Valid(Resource source,TerrainDataOperations native)=>source.Call("water_valid").AsBool()&&native.biomes_valid(source)&&native.volumes_valid(source)&&native.cave_biomes_valid(source);
    private void Status(string text){if(Live())_owner!.Get("status").As<Label>().Text=text;}
    public void start(Control owner,string destination){if(_running)return;_running=true;_owner=owner;_session=owner.Get("session").As<RefCounted>();_ = Run(destination,GetTree());}
    private async Task Run(string destination,SceneTree tree)
    {
        try{result=await Save(destination,tree);}
        catch(Exception failure){GD.PushError(failure.ToString());Status("Could not save the environment.");result=Error.Failed;}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
    private async Task<Error> Save(string destination,SceneTree tree)
    {
        var owner=_owner!;var session=_session!;var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","flush",owner,new Godot.Collections.Array());var returned=await ToSignal(bridge,"completed");if(!Current()||returned.Length==0||returned[0].VariantType!=Variant.Type.Bool||!returned[0].AsBool())return Error.Busy;
        var canvas=owner.Get("canvas").As<Control>();canvas.Call("cancel_all");var native=Engine.GetSingleton("KiwiNativeServices").Call("service","environment_workspace").As<EnvironmentWorkspaceOperations>();
        while(Current()&&owner.Get("_generation_jobs").AsGodotArray().Count>0)await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current())return Error.Busy;
        var document=session.Get("document").As<Resource>();foreach(var component in document.Get("components").AsGodotArray())
        {
            string id=component.As<Resource>().Get("id").AsString();var source=_documents.terrain(document,id);if(source==null||Valid(source,_terrain))continue;native.regenerate_terrain(owner,id,new Settings(),false,true);while(Current()&&owner.Get("_generation_jobs").AsGodotArray().Count>0)await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current())return Error.Busy;document=session.Get("document").As<Resource>();source=_documents.terrain(document,id);if(source==null||!Valid(source,_terrain)){Status("Terrain generation must finish before this environment can be saved.");return Error.CantCreate;}
        }
        document=session.Get("document").As<Resource>();document.Get("workspace_state").AsGodotDictionary().Merge(native.editor_state(owner),true);var errors=_documents.validate(document);if(errors.Length>0){Status(errors[0]);return Error.InvalidData;}canvas.Call("sync");var renderer=canvas.Get("renderer").As<Node3D>();
        while(Current()&&(renderer.Get("pending_assets").AsGodotDictionary().Count>0||renderer.Get("pending_chunks").AsGodotDictionary().Count>0))await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current())return Error.Busy;
        long revision=session.Get("revision").AsInt64();using var saved=session.Get("document").As<Resource>().Call("snapshot").As<Resource>();
        if(DisplayServer.GetName()!="headless")
        {
            // Force a completed preview even when a static/minimized window skips post-draw signals.
            RenderingServer.ForceSync();RenderingServer.ForceDraw(false);if(!Current())return Error.Busy;using var image=canvas.Get("viewport").As<SubViewport>().GetTexture().GetImage();image.Resize(240,160,Image.Interpolation.Lanczos);saved.Set("preview_png",image.SavePngToBuffer());
        }
        if(!Live())return Error.Busy;var error=ResourceSaver.Save(saved,destination);if(error==Error.Ok){if(session.Get("revision").AsInt64()==revision)session.Set("dirty",false);if(Current()){owner.Set("path",destination);Status("Saved "+destination);}owner.EmitSignal("environment_saved",destination,session);GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").Call("refresh_filesystem");}else Status("Could not save the environment.");return error;
    }
}
