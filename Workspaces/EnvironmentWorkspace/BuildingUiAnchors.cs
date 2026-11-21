using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingUiOperations
{
    public void anchors(Control workspace,string id)
    {
        var session=Session(workspace);var document=session.Get("document").As<Resource>();var item=_documents.component(document,id);if(item==null)return;var window=new Window {Title="Align component anchors",Size=new Vector2I(430,240),Transient=true};workspace.AddChild(window);window.CloseRequested+=window.QueueFree;var panel=new VBoxContainer();panel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);panel.AddThemeConstantOverride("separation",8);window.AddChild(panel);var sourceAnchors=_modules.anchors(item);var from=new OptionButton();panel.AddChild(from);foreach(var value in sourceAnchors)from.AddItem("Moving anchor · "+value.AsGodotDictionary()["name"].AsString());var target=new OptionButton();panel.AddChild(target);var ids=new List<string>();foreach(var value in document.Get("components").AsGodotArray()){var other=value.As<Resource>();string otherId=other.Get("id").AsString();if(otherId==id||_documents.is_descendant(document,otherId,id))continue;ids.Add(otherId);target.AddItem(other.Get("title").AsString());}var to=new OptionButton();panel.AddChild(to);var targetAnchors=new GArray();void Refresh(long index){to.Clear();targetAnchors.Clear();if(index<0||index>=ids.Count)return;var other=_documents.component(Session(workspace).Get("document").As<Resource>(),ids[(int)index]);if(other==null)return;foreach(var value in _modules.anchors(other)){targetAnchors.Add(value);to.AddItem("Target anchor · "+value.AsGodotDictionary()["name"].AsString());}}target.ItemSelected+=Refresh;Refresh(0);var mate=new CheckButton {Text="Face anchors toward each other",ButtonPressed=true};panel.AddChild(mate);var apply=new Button {Text="Align",Disabled=ids.Count==0};panel.AddChild(apply);apply.Pressed+=()=>{if(target.Selected<0||target.Selected>=ids.Count||to.Selected<0||to.Selected>=targetAnchors.Count||from.Selected<0||from.Selected>=sourceAnchors.Count)return;string error=_modules.snap(Session(workspace),id,sourceAnchors[from.Selected].AsGodotDictionary()["pose"].AsTransform3D(),ids[target.Selected],targetAnchors[to.Selected].AsGodotDictionary()["pose"].AsTransform3D(),mate.ButtonPressed);workspace.Get("status").As<Label>().Text=error.Length>0?error:"Component aligned";if(error.Length==0)window.QueueFree();};window.PopupCentered();
    }
    public void cancel(Control workspace)
    {if(workspace.HasMeta("building_plan")){var plan=workspace.GetMeta("building_plan").As<Control>();if(GodotObject.IsInstanceValid(plan))plan.Call("cancel");}}
    public void frame(Control workspace)
    {var canvas=workspace.Get("canvas").As<Control>();canvas.Call("frame");double aspect=canvas.Size.X/Math.Max(1.0,canvas.Size.Y);if(aspect<1){canvas.Set("distance",canvas.Get("distance").AsDouble()/Math.Max(.2,aspect));canvas.Call("update_camera");}}
}
