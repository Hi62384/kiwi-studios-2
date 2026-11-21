using Godot;
using System;
using System.Linq;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingInspectorNativeTest : Node
{
    private int _checks;
    private void Check(bool value,string title){if(!value)throw new Exception(title);_checks++;GD.Print("PASS ",title);}
    private async Task Settle(int frames=8){for(int index=0;index<frames;index++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    private static BuildingEditOperations Edits()=>Engine.GetSingleton("KiwiNativeServices").Call("service","building_edit").As<BuildingEditOperations>();
    private async Task Drain(RefCounted session)
    {ulong deadline=Time.GetTicksMsec()+20000;while(Edits().pending(session).Count>0&&Time.GetTicksMsec()<deadline)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);Check(Edits().pending(session).Count==0,"Inspector edit finishes within its bounded test window");await Settle();}
    public override async void _Ready()
    {
        Control? workspace=null;try
        {
            GetTree().Root.Size=new Vector2I(1440,950);workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);await Settle();var session=workspace.Get("session").As<RefCounted>();using var buildings=new BuildingSessionOperations();using var documents=new ModelDocumentOperations();var root=buildings.add(session,Vector3.Zero,1)!;string id=root.Get("id").AsString();var selected=session.Get("selected").AsGodotArray();selected.Clear();selected.Add(id);session.EmitSignal("changed");await Settle();
            Resource Source()=>buildings.source(documents.component(session.Get("document").As<Resource>(),id))!;
            SpinBox Number(string title)=>workspace.FindChildren("*","SpinBox",true,false).OfType<SpinBox>().First(number=>number.GetParent().GetChildren().OfType<Label>().Any(label=>label.Text==title));
            Button FindButton(string title)=>workspace.FindChildren("*","Button",true,false).OfType<Button>().First(button=>button.Text==title);
            int History()=>session.Get("_undo").AsGodotArray().Count;
            double original=Source().Get("wall_thickness").AsDouble();int history=History();var thickness=Number("Wall thickness");thickness.Value=original+.12;await Drain(session);Check(Math.Abs(Source().Get("wall_thickness").AsDouble()-original-.12)<.0001&&History()==history+1,"Native inspector changes a building dimension as one undoable source edit");session.Call("undo");await Settle();Check(Math.Abs(Source().Get("wall_thickness").AsDouble()-original)<.0001,"Undo restores the original authored dimension");session.Call("redo");await Settle();
            history=History();FindButton("＋ Level").EmitSignal(Button.SignalName.Pressed);await Drain(session);Check(Source().Get("floors").AsGodotArray().Count==2&&History()==history+1,"Native add-level control creates validated geometry in one history entry");
            var styles=workspace.FindChildren("*","OptionButton",true,false).OfType<OptionButton>().First(choice=>choice.ItemCount>0&&choice.GetItemText(0).StartsWith("Style · ",StringComparison.Ordinal));int cabin=Enumerable.Range(0,styles.ItemCount).First(index=>styles.GetItemText(index)=="Cabin");styles.Select(cabin);styles.EmitSignal(OptionButton.SignalName.ItemSelected,cabin);await Drain(session);Check(Source().Get("style").AsString()=="Cabin"&&Source().Get("facade_detail").AsInt32()==2,"Native style selector updates authored parameters and regenerated facade together");
            var cut=workspace.FindChildren("*","CheckButton",true,false).OfType<CheckButton>().First(button=>button.Text=="Interior cutaway");cut.ButtonPressed=true;await Settle(16);var plan=workspace.GetMeta("building_plan").As<Control>();Check(plan.Get("cutaway").AsBool()&&plan.Visible,"Native cutaway control opens the split plan and enables its preview");
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();await Settle();workspace=null;GD.Print("BUILDING INSPECTOR: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception failure){GD.PushError(failure.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
}
