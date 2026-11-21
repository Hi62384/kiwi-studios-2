using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;

public partial class EnvironmentClimateInspectorTest : Node
{
    private int _checks;
    private void Check(bool value,string label){if(!value)throw new Exception(label);_checks++;GD.Print("PASS ",label);}
    private async Task Settle(){for(int i=0;i<8;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    public override async void _Ready()
    {
        Control? workspace=null;
        try
        {
            workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);await Settle();
            var session=workspace.Get("session").As<RefCounted>();Resource Document()=>session.Get("document").As<Resource>();Resource Climate()=>Document().Get("climate").As<Resource>();
            void Show(){var parent=workspace.Get("properties").As<VBoxContainer>();foreach(Node child in parent.GetChildren()){parent.RemoveChild(child);child.QueueFree();}workspace.Call("_climate_properties");}
            SpinBox Number(string label)=>workspace.FindChildren("*","SpinBox",true,false).OfType<SpinBox>().First(n=>n.GetParent().GetChildren().OfType<Label>().Any(t=>t.Text==label));
            Show();int count=session.Get("_undo").AsGodotArray().Count;double temperature=Climate().Get("temperature").AsDouble();Number("Temperature (°C)").Value=temperature+3;
            Check(Math.Abs(Climate().Get("temperature").AsDouble()-temperature-3)<.001&&session.Get("_undo").AsGodotArray().Count==count+1,"Climate number control makes one validated undoable edit");
            session.Call("undo");Check(Math.Abs(Climate().Get("temperature").AsDouble()-temperature)<.001,"Climate inspector undo restores authored state");session.Call("redo");Check(Math.Abs(Climate().Get("temperature").AsDouble()-temperature-3)<.001,"Climate inspector redo restores changed value");await Settle();Show();
            var menu=workspace.FindChildren("*","MenuButton",true,false).OfType<MenuButton>().First(b=>b.Text=="＋ Add weather region");menu.GetPopup().EmitSignal(PopupMenu.SignalName.IdPressed,2);
            Check(Climate().Get("regions").AsGodotArray().Count==1&&Climate().Get("regions").AsGodotArray()[0].AsGodotDictionary()["shape"].AsString()=="Ellipsoid","Region menu adds selected shape");await Settle();Show();Number("Radius").Value=23;
            Check(Climate().Get("regions").AsGodotArray()[0].AsGodotDictionary()["size"].AsVector3().IsEqualApprox(Vector3.One*46),"Region radius control updates all dimensions");await Settle();Show();Number("Local intensity").Value=.4;
            Check(Math.Abs(Climate().Get("regions").AsGodotArray()[0].AsGodotDictionary()["overrides"].AsGodotDictionary()["weather_intensity"].AsDouble()-.4)<.001,"Region intensity control updates nested overrides");
            await Settle();var panel=workspace.Get("properties").As<VBoxContainer>();foreach(Node node in panel.GetChildren()){panel.RemoveChild(node);node.QueueFree();}workspace.Call("_environment_properties");
            double energy=Document().Get("sunlight").AsGodotDictionary()["energy"].AsDouble();Number("Sun energy").Value=energy+1;Check(Math.Abs(Document().Get("sunlight").AsGodotDictionary()["energy"].AsDouble()-energy-1)<.001,"Lighting energy control updates authored sunlight");session.Call("undo");Check(Math.Abs(Document().Get("sunlight").AsGodotDictionary()["energy"].AsDouble()-energy)<.001,"Lighting control undo restores authored sunlight");
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();workspace=null;await Settle();GD.Print("CLIMATE INSPECTOR: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
}
