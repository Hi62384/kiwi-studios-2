using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWaterToolTest : Node
{
    private int _checks;
    private void Check(bool value,string title){if(!value)throw new Exception(title);_checks++;GD.Print("PASS ",title);}
    private async Task Settle(){for(int i=0;i<8;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    private async Task Drain(Control workspace)
    {ulong deadline=Time.GetTicksMsec()+20000;while(workspace.Get("_generation_jobs").AsGodotArray().Count>0&&Time.GetTicksMsec()<deadline)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);Check(workspace.Get("_generation_jobs").AsGodotArray().Count==0,"Water path generation completes within its bounded test window");await Settle();}
    public override async void _Ready()
    {
        Control? workspace=null;
        try
        {
            GetTree().Root.Size=new Vector2I(1400,900);var document=new KiwiEnvironmentDocument();var terrain=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_terrain.gd").New().As<Resource>();terrain.Set("resolution",17);terrain.Set("dimensions",new Vector2(16,16));
            var hydrology=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_hydrology.gd").New().As<Resource>();hydrology.Set("automatic_rivers",false);hydrology.Set("automatic_lakes",false);hydrology.Get("manual_rivers").AsGodotArray().Add(new Settings {["id"]="native-handle-river",["points"]=new[]{new Vector3(-6,0,-6),Vector3.Zero,new Vector3(6,0,6)},["width"]=1.0,["depth"]=.5});terrain.Set("hydrology",hydrology);Check(terrain.Call("prepare_water").AsBool(),"Water handle fixture generates valid physical river data");
            var component=document.Call("add_terrain",terrain).As<Resource>();string id=component.Get("id").AsString();workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);workspace.Call("open_source",document);var session=workspace.Get("session").As<RefCounted>();session.Call("select",id);await Settle();
            var canvas=workspace.Get("canvas").As<Control>();var camera=canvas.Get("camera").As<Camera3D>();camera.Position=new Vector3(0,12,8);camera.LookAt(Vector3.Zero);canvas.Set("environment_tool","Water paths");canvas.Set("snap",false);var tool=canvas.Get("water_tool").As<RefCounted>();
            Resource Current()=>session.Call("environment").As<Resource>().Call("terrain",id).As<Resource>();
            Vector3[] Authored()=>Current().Get("hydrology").As<Resource>().Get("manual_rivers").AsGodotArray()[0].AsGodotDictionary()["points"].AsVector3Array();
            Vector3[] Displayed()=>tool.Call("path_points",tool.Call("target"),0).AsVector3Array();
            Vector2 Screen(Vector3 point)=>canvas.Call("project",point).AsVector2();
            void Mouse(bool pressed,Vector2 point,bool shift=false)=>canvas.Call("_gui_input",new InputEventMouseButton {ButtonIndex=MouseButton.Left,Pressed=pressed,Position=point,ShiftPressed=shift});
            int History()=>session.Get("_undo").AsGodotArray().Count;
            var initial=Authored();int history=History();var screen=Screen(Displayed()[1]);Mouse(true,screen);
            Check(tool.Get("_drag").AsGodotDictionary().Count>0&&PointIndex(tool)==1,"Clicking a visible river handle begins the matching native drag");
            canvas.Call("_gui_input",new InputEventMouseMotion {Position=screen+new Vector2(45,0),Relative=new Vector2(45,0)});Check(Authored()[1]==initial[1],"Dragging previews privately before replacing the authored water source");Mouse(false,screen+new Vector2(45,0));await Drain(workspace);
            var moved=Authored();Check(!moved[1].IsEqualApprox(initial[1])&&moved[1].Y==initial[1].Y&&History()==history+1,"Releasing a follow-terrain river handle moves its path in one undo action while preserving authored height");
            session.Call("undo");await Settle();Check(Authored()[1]==initial[1],"Undo restores the original river control point");session.Call("redo");await Settle();Check(Authored()[1]==moved[1],"Redo restores the moved river control point");
            history=History();screen=Screen(Displayed()[1]);Mouse(true,screen);canvas.Call("_gui_input",new InputEventMouseMotion {Position=screen+new Vector2(20,0)});canvas.Call("_gui_input",new InputEventKey {Keycode=Key.Escape,Pressed=true});Check(tool.Get("_drag").AsGodotDictionary().Count==0&&History()==history&&Authored()[1]==moved[1],"Escape cancels a handle preview without history or source changes");
            canvas.Call("_gui_input",new InputEventKey {Keycode=Key.Delete,Pressed=true});await Drain(workspace);Check(Authored().Length==2&&History()==history+1,"Delete removes a selected river point as one source edit");session.Call("undo");await Settle();
            var displayed=Displayed();Mouse(true,Screen(displayed[0].Lerp(displayed[1],.5f)),true);await Drain(workspace);Check(Authored().Length==4,"Shift-click inserts a new point on the nearest visible river segment");
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();await Settle();workspace=null;GD.Print("ENVIRONMENT WATER TOOL: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception failure){GD.PushError(failure.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
    private static int PointIndex(RefCounted tool)=>tool.Get("point_index").AsInt32();
}
