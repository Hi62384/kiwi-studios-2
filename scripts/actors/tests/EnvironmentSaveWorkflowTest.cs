using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentSaveWorkflowTest : Node
{
    private int _checks;
    private void Check(bool value,string title){if(!value)throw new Exception(title);_checks++;GD.Print("PASS ",title);}
    private async Task Frames(int count=6){for(int i=0;i<count;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    private async Task<PopupPanel> Dialog(Control workspace)
    {ulong deadline=Time.GetTicksMsec()+15000;while(Time.GetTicksMsec()<deadline){var dialog=workspace.FindChildren("*","PopupPanel",true,false).OfType<PopupPanel>().FirstOrDefault(node=>node.Visible&&node.GetScript().As<Script>()?.ResourcePath=="res://scripts/actors/core/actor_project_resource_save_dialog.gd");if(dialog!=null)return dialog;await Frames(1);}throw new Exception("Save dialog did not appear within its bounded window");}
    private async Task Submit(Control workspace,string name)
    {var dialog=await Dialog(workspace);dialog.Get("filename").As<LineEdit>().Text=name;dialog.Call("_save");}
    public override async void _Ready()
    {
        Control? workspace=null;
        try
        {
            using var setup=new GDScript {SourceCode="extends RefCounted\nfunc project(folder: String) -> void:\n\tDirAccess.make_dir_recursive_absolute(folder.path_join(\".proj/.trash\"))\n\tvar value:=Project.create(\"Native save workflow\")\n\tResourceSaver.save(value,folder.path_join(\".proj/Project.tres\"))\n\tvalue.take_over_path(folder.path_join(\".proj/Project.tres\"))\n\tStaticData.set_loaded_project(value)\n"};Check(setup.Reload()==Error.Ok,"Shared project fixture compiles");using var fixture=setup.New().As<RefCounted>();string folder=ProjectSettings.GlobalizePath("user://native-environment-save");fixture.Call("project",folder);
            GetTree().Root.Size=new Vector2I(1440,900);workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);Check(workspace.Call("open_source",default(Variant),new Settings()).AsBool(),"Fresh environment opens for native save workflow");await Frames(12);var session=workspace.Get("session").As<RefCounted>();
            var save=new EnvironmentWorkspaceSaveJob();workspace.AddChild(save);save.start_mode(workspace,"save_as");var completion=ToSignal(save,"completed");await Submit(workspace,"Native environment");await completion;Check(save.result==Error.Ok&&Godot.FileAccess.FileExists(folder.PathJoin("Native environment.tres")),"Native Save As dialog writes a complete environment");
            await Frames(2);session.Call("begin");session.Get("document").As<Resource>().Set("title","Saved through shortcut");session.Call("commit","Rename test environment");workspace.Call("_unhandled_key_input",new InputEventKey {Pressed=true,CtrlPressed=true,Keycode=Key.S});var shortcut=workspace.GetChildren().OfType<EnvironmentWorkspaceSaveJob>().First();await ToSignal(shortcut,"completed");var loaded=ResourceLoader.Load(folder.PathJoin("Native environment.tres"),"",ResourceLoader.CacheMode.Ignore);Check(loaded.Get("title").AsString()=="Saved through shortcut"&&!session.Get("dirty").AsBool(),"Ctrl+S saves the existing path without reopening Save As");await Frames();
            string id=session.Get("document").As<Resource>().Get("components").AsGodotArray()[0].As<Resource>().Get("id").AsString();session.Call("select",id);workspace.Call("_save_component");await Submit(workspace,"Reusable terrain");await Frames(12);Check(Godot.FileAccess.FileExists(folder.PathJoin("Reusable terrain.tres")),"Reusable-component workflow writes the selected hierarchy");
            workspace.Call("_bake_terrain",id);await Submit(workspace,"Baked terrain");await Frames(12);var baked=ResourceLoader.Load(folder.PathJoin("Baked terrain.res"),"",ResourceLoader.CacheMode.Ignore);Check(baked!=null&&baked.Call("validate").AsStringArray().Length==0&&baked.Get("components").AsGodotArray().Count>1,"Native bake workflow saves an independent valid editable model");
            var cancel=new EnvironmentWorkspaceSaveJob();workspace.AddChild(cancel);cancel.start_mode(workspace,"save_as");var cancelled=ToSignal(cancel,"completed");(await Dialog(workspace)).Hide();await cancelled;Check(cancel.result==Error.Skip&&workspace.Get("path").AsString().EndsWith("Native environment.tres",StringComparison.Ordinal),"Canceling Save As preserves the current document path");
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();workspace=null;await Frames();GD.Print("ENVIRONMENT SAVE WORKFLOW: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());workspace?.QueueFree();await Frames();GetTree().Quit(1);}
    }
}
