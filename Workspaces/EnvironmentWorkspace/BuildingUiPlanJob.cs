using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingUiPlanJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    public Control? result {get;private set;}
    private bool _running;
    private readonly BuildingUiOperations _ui=new();
    private readonly BuildingSessionOperations _buildings=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private bool Current(Control workspace,RefCounted session)=>GodotObject.IsInstanceValid(this)&&IsInsideTree()&&GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree()&&workspace.Get("session").As<RefCounted>()==session;
    public void start(Control workspace,string kind,Resource? root,int mode,bool fitFirst,int levels){if(_running)return;_running=true;_ = Run(workspace,kind,root,mode,fitFirst,levels,GetTree());}
    private async Task Run(Control workspace,string kind,Resource? root,int mode,bool fitFirst,int levels,SceneTree tree)
    {
        var session=workspace.Get("session").As<RefCounted>();try
        {
            if(kind=="restore")
            {var document=session.Get("document").As<Resource>();var state=Get(document.Get("workspace_state").AsGodotDictionary(),"architecture_plan",new Settings()).AsGodotDictionary().Duplicate(true);await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current(workspace,session))return;root=_ui.restore_now(workspace,document,state);if(root==null)return;mode=Get(state,"mode",1).AsInt32();fitFirst=false;}
            var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","flush",workspace,new GArray());var returned=await ToSignal(bridge,"completed");if(returned.Length==0||!returned[0].AsBool()||!Current(workspace,session))return;if(kind=="create"){var canvas=workspace.Get("canvas").As<Control>();_buildings.add(session,canvas.Get("target").AsVector3(),levels);canvas.Call("request_sync");canvas.Call("frame");return;}if(root==null)return;var stateResult=_ui.show_plan_now(workspace,root,mode,fitFirst);result=stateResult["plan"].As<Control>();if(stateResult["frame"].AsBool()){await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(Current(workspace,session))_ui.frame(workspace);}
        }
        catch(Exception failure){GD.PushError(failure.ToString());}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
