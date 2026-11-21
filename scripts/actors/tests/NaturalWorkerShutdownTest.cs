using Godot;
using System;
using System.Linq;

public partial class NaturalWorkerShutdownTest : Node
{
    private NaturalGenerationJob? _job;
    public override async void _Ready()
    {
        try
        {
            if(OS.GetCmdlineUserArgs().Contains("--workspace"))
            {
                var workspace=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace.gd").New().As<Control>();AddChild(workspace);await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
                var source=workspace.Get("session").As<RefCounted>().Call("add","Tree / Oak",new Godot.Collections.Dictionary{["levels"]=1}).As<Resource>();
                GD.Load<GDScript>("res://Workspaces/ModelWorkspace/natural_edit.gd").Call("request",workspace,source.Get("id"),"height",11.0,false);await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
                GD.Print("NATURAL SHUTDOWN: requesting application exit with workspace edit "+(workspace.GetMeta("natural_edit",new Godot.Collections.Dictionary()).AsGodotDictionary().Count>0?"pending":"completed"));
            }
            else
            {
                _job=new NaturalGenerationJob();_job.start("Tree / Oak",new Godot.Collections.Dictionary{["levels"]=6,["seed"]=314159,["max_faces"]=100000});
                await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
                GD.Print("NATURAL SHUTDOWN: requesting application exit with generation job "+(_job.complete()?"completed":"pending"));
            }
            GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());GetTree().Quit(1);}
    }
}
