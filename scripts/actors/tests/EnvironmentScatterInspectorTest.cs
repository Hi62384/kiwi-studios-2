using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentScatterInspectorTest : Node
{
    private int _checks;
    private void Check(bool value,string title){if(!value)throw new Exception(title);_checks++;GD.Print("PASS ",title);}
    private async Task Settle(){for(int i=0;i<6;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    public override async void _Ready()
    {
        Control? workspace=null;try
        {
            workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);await Settle();var session=workspace.Get("session").As<RefCounted>();var document=session.Get("document").As<Resource>();var layer=document.Call("add_group","Test scatter").As<Resource>();var scatter=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_scatter.gd").New().As<Resource>();document.Get("component_settings").AsGodotDictionary()[layer.Get("id")]=new Settings {["kind"]="scatter",["scatter"]=scatter};
            var panel=workspace.Get("properties").As<VBoxContainer>();foreach(Node child in panel.GetChildren()){panel.RemoveChild(child);child.QueueFree();}using var inspector=new EnvironmentScatterInspector();inspector.properties(workspace,layer,scatter);
            SpinBox Number(string label)=>panel.FindChildren("*","SpinBox",true,false).OfType<SpinBox>().First(n=>n.GetParent().GetChildren().OfType<Label>().Any(l=>l.Text==label));
            int history=session.Get("_undo").AsGodotArray().Count;Number("Density / m²").Value=.7;Check(Math.Abs(scatter.Get("density").AsDouble()-.7)<.001&&session.Get("_undo").AsGodotArray().Count==history+1,"Scatter density control records one history edit");
            Number("Region X").Value=-13;Check(Math.Abs(scatter.Get("region").AsRect2().Position.X+13)<.001,"Scatter region control writes the selected rectangle component");
            scatter.Get("paint_regions").AsGodotArray().Add(new Vector3(1,2,3));scatter.Get("erase_regions").AsGodotArray().Add(new Vector3(2,3,4));panel.FindChildren("*","Button",true,false).OfType<Button>().First(b=>b.Text=="Clear painted regions").EmitSignal(Button.SignalName.Pressed);Check(scatter.Get("paint_regions").AsGodotArray().Count==0&&scatter.Get("erase_regions").AsGodotArray().Count==0,"Clear control clears both typed paint masks");
            session.Call("undo");var restored=session.Get("document").As<Resource>().Get("component_settings").AsGodotDictionary()[layer.Get("id")].AsGodotDictionary()["scatter"].As<Resource>();Check(restored.Get("paint_regions").AsGodotArray().Count==1&&restored.Get("erase_regions").AsGodotArray().Count==1,"Undo restores the scatter paint masks");
            Number("Density / m²").Value=.9;Check(Math.Abs(restored.Get("density").AsDouble()-.7)<.001,"Stale inspector controls cannot edit a replaced undo snapshot");session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();workspace=null;await Settle();GD.Print("SCATTER INSPECTOR: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
}
