using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentCavePathTest : Node
{
    private int _checks;
    private void Check(bool value,string title){if(!value)throw new Exception(title);_checks++;GD.Print("PASS ",title);}
    private async Task Settle(){for(int i=0;i<8;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    private async Task Drain(Control workspace)
    {ulong deadline=Time.GetTicksMsec()+20000;while(workspace.Get("_generation_jobs").AsGodotArray().Count>0&&Time.GetTicksMsec()<deadline)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);Check(workspace.Get("_generation_jobs").AsGodotArray().Count==0,"Cave path regeneration finishes within the bounded test window");await Settle();}
    public override async void _Ready()
    {
        Control? workspace=null;
        try
        {
            GetTree().Root.Size=new Vector2I(1400,900);var document=new KiwiEnvironmentDocument();var terrain=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_terrain.gd").New().As<Resource>();terrain.Set("resolution",17);terrain.Set("dimensions",new Vector2(16,16));
            var cave=new KiwiTerrainCave();cave.Set("roughness",0.0);cave.Set("radius_variation",0.0);cave.Get("paths").AsGodotArray().Add(new[]{new Vector3(-4,-2,0),new Vector3(0,-2,0),new Vector3(4,-2,0)});cave.Set("chambers",new[]{new Vector4(0,-3,3,1.5f)});terrain.Get("caves").AsGodotArray().Add(cave);Check(terrain.Call("prepare_volumes").AsBool(),"Cave handle fixture creates valid native volume geometry");
            var component=document.Call("add_terrain",terrain).As<Resource>();string id=component.Get("id").AsString();workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);workspace.Call("open_source",document);var session=workspace.Get("session").As<RefCounted>();session.Call("select",id);await Settle();
            var canvas=workspace.Get("canvas").As<Control>();var camera=canvas.Get("camera").As<Camera3D>();camera.Position=new Vector3(0,5,10);camera.LookAt(new Vector3(0,-2,0));canvas.Set("environment_tool","Cave path");var tool=canvas.Get("cave_tool").As<RefCounted>();
            Resource Current()=>session.Call("environment").As<Resource>().Call("terrain",id).As<Resource>();
            Resource Cave()=>Current().Get("caves").AsGodotArray()[0].As<Resource>();
            Vector3[] Path()=>Cave().Get("paths").AsGodotArray()[0].AsVector3Array();
            int History()=>session.Get("_undo").AsGodotArray().Count;
            Vector2 Screen(Vector3 point)=>canvas.Call("project",point).AsVector2();
            void Mouse(bool pressed,Vector2 point,bool shift=false)=>canvas.Call("_gui_input",new InputEventMouseButton {ButtonIndex=MouseButton.Left,Pressed=pressed,Position=point,ShiftPressed=shift});
            var initial=Path();int history=History();var screen=Screen(initial[0]);Mouse(true,screen);Check(tool.Get("_drag").AsGodotDictionary().Count>0&&tool.Get("path_index").AsInt32()==0&&tool.Get("point_index").AsInt32()==0,"Clicking a visible tunnel point selects its native path handle");
            canvas.Call("_gui_input",new InputEventMouseMotion {Position=screen+new Vector2(35,0)});Check(Path()[0]==initial[0],"Tunnel dragging keeps authored geometry private until release");Mouse(false,screen+new Vector2(35,0));await Drain(workspace);
            var moved=Path();Check(!moved[0].IsEqualApprox(initial[0])&&History()==history+1&&Current().Call("volumes_valid").AsBool(),"Releasing a tunnel point regenerates complete real geometry as one undo action");session.Call("undo");await Settle();Check(Path()[0]==initial[0],"Undo restores the tunnel source point");session.Call("redo");await Settle();Check(Path()[0]==moved[0],"Redo restores the edited tunnel source point");
            history=History();screen=Screen(Path()[0]);Mouse(true,screen);canvas.Call("_gui_input",new InputEventMouseMotion {Position=screen+new Vector2(20,0)});canvas.Call("_gui_input",new InputEventKey {Keycode=Key.Escape,Pressed=true});Check(tool.Get("_drag").AsGodotDictionary().Count==0&&History()==history&&Path()[0]==moved[0],"Escape cancels a tunnel handle without changing source or history");
            var chamber=Cave().Get("chambers").AsVector4Array()[0];Mouse(true,Screen(new Vector3(chamber.X,chamber.Y,chamber.Z)));Check(tool.Get("path_index").AsInt32()==-1,"A chamber handle can be selected independently of tunnel points");canvas.Call("_gui_input",new InputEventKey {Keycode=Key.Escape,Pressed=true});canvas.Call("_gui_input",new InputEventKey {Keycode=Key.Delete,Pressed=true});await Drain(workspace);Check(Cave().Get("chambers").AsVector4Array().Length==0,"Delete removes the selected chamber while preserving the tunnel");session.Call("undo");await Settle();
            var path=Path();Mouse(true,Screen(path[0].Lerp(path[1],.5f)),true);await Drain(workspace);Check(Path().Length==4,"Shift-click inserts a tunnel point on its nearest visible segment");
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();await Settle();workspace=null;GD.Print("ENVIRONMENT CAVE PATH: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception failure){GD.PushError(failure.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
}
