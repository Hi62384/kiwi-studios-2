using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

public partial class RigUiTest : Node
{
    private static IEnumerable<Node> Descendants(Node root)
    {foreach(Node child in root.GetChildren()){yield return child;foreach(Node nested in Descendants(child)) yield return nested;}}
    private async Task Settle(){for(int i=0;i<5;i++) await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    public override async void _Ready()
    {
        try
        {
            GetTree().Root.Size=new Vector2I(1440,960);GetTree().Root.GuiEmbedSubwindows=true;
            var workspace=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace.gd").New().As<Control>();AddChild(workspace);workspace.Call("open_source",new KiwiModelDocument());await Settle();
            var session=workspace.Get("session").As<RefCounted>();var first=session.Call("add","Box").As<Resource>();var second=session.Call("add","Box").As<Resource>();await Settle();
            var hierarchy=workspace.Get("hierarchy").As<ModelHierarchy>();var targetRow=hierarchy.GetRoot().GetFirstChild().GetNext();Vector2 target=hierarchy.GetItemAreaRect(targetRow,0).GetCenter();var payload=new Godot.Collections.Dictionary{["kiwi_model_tree"]=hierarchy.GetInstanceId(),["ids"]=new Godot.Collections.Array<string>{first.Get("id").AsString()}};
            if(!hierarchy._CanDropData(target,payload))throw new Exception("Native hierarchy rejected a valid component parenting drop.");hierarchy._DropData(target,payload);
            var document=session.Get("document").As<Resource>();if(document.Call("component",first.Get("id")).As<Resource>().Get("parent_id").AsString()!=second.Get("id").AsString())throw new Exception("Native hierarchy drop did not parent the component.");
            session.Call("undo");await Settle();document=session.Get("document").As<Resource>();if(document.Call("component",first.Get("id")).As<Resource>().Get("parent_id").AsString().Length!=0)throw new Exception("Native hierarchy reparent did not undo.");
            payload["kiwi_model_tree"]=0;if(hierarchy._CanDropData(target,payload))throw new Exception("Native hierarchy accepted another tree's drag payload.");
            GD.Print("PASS native hierarchy drop parents components, supports undo and rejects foreign drags");
            var ui=workspace.Get("rig_ui").As<RefCounted>();ui.Call("quick_rig");await Settle();
            var quick=workspace.GetNode<PopupPanel>("QuickRig");Descendants(quick).OfType<Button>().Single(b=>b.Text.StartsWith("✦ Auto Rig",StringComparison.Ordinal)).EmitSignal(BaseButton.SignalName.Pressed);await Settle();
            var editor=ui.Call("editor").As<RefCounted>().Get("_native").As<RigEditor>();
            if(editor.rig()?.Get("bones").AsGodotArray().Count!=6) throw new Exception("Quick Rig button did not create the fitted native chain.");
            GD.Print("PASS native Quick Rig button creates an editable fitted chain");
            ui.Call("templates");await Settle();var popup=workspace.GetNode<PopupPanel>("RigTemplates");Descendants(popup).OfType<Button>().Single(b=>b.Text=="Humanoid").EmitSignal(BaseButton.SignalName.Pressed);await Settle();
            if(editor.rig()?.Get("title").AsString()!="Humanoid Rig"||new RigMath().validate(editor.rig()!.Get("bones").AsGodotArray()).Length>0) throw new Exception("Template menu selection did not create a valid humanoid.");
            GD.Print("PASS native categorized template popup creates the chosen rig");
            ui.Call("set_mode","Edit");await Settle();var properties=workspace.Get("properties").As<Control>();
            var name=Descendants(properties).OfType<LineEdit>().Single(input=>input.PlaceholderText=="Bone name");name.Text="Edited root";name.EmitSignal(LineEdit.SignalName.TextSubmitted,name.Text);await Settle();
            if(editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["name"].AsString()!="Edited root") throw new Exception("Native inspector rename callback did not reach the model.");
            session.Call("undo");await Settle();if(editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["name"].AsString()=="Edited root") throw new Exception("Inspector rename did not undo.");
            GD.Print("PASS native bone-name inspector callback updates model and undo");
            var radiusLabel=Descendants(properties).OfType<Label>().Single(label=>label.Text=="Envelope radius");var number=radiusLabel.GetParent().GetChildren().OfType<Control>().Last();double original=editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["radius"].AsDouble();number.Set("value",original+.2);double expected=number.Get("value").AsDouble();await Settle();
            if(Math.Abs(editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["radius"].AsDouble()-expected)>.00001||expected-original<.15) throw new Exception("Draggable-number callback failed across the native inspector boundary: expected "+expected+", actual "+editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["radius"].AsDouble());
            session.Call("undo");await Settle();if(Math.Abs(editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["radius"].AsDouble()-original)>.00001) throw new Exception("Inspector radius change did not undo.");
            GD.Print("PASS native inspector numeric property updates live and undoes exactly");
            ui.Call("set_mode","Pose");await Settle();var slider=Descendants(properties).OfType<HSlider>().Single(s=>s.MinValue==-150);var before=editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["rotation"].AsVector3();slider.Value=35;await Settle();
            if(editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["rotation"].AsVector3().IsEqualApprox(before)) throw new Exception("Native bend slider did not change the selected bone.");
            session.Call("undo");await Settle();if(!editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["rotation"].AsVector3().IsEqualApprox(before)) throw new Exception("Native bend slider did not undo exactly.");
            GD.Print("PASS native pose bend slider changes the selected bone and supports exact undo");workspace.QueueFree();await Settle();GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());GetTree().Quit(1);}
    }
}
