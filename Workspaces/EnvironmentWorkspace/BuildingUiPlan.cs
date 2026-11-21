using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingUiOperations
{
    private readonly BuildingSessionOperations _buildings=new();
    public Settings show_plan_now(Control workspace,Resource root,int mode,bool fitFirst)
    {
        var plan=workspace.HasMeta("building_plan")?workspace.GetMeta("building_plan").As<Control>():null;bool first=!GodotObject.IsInstanceValid(plan);var canvas=workspace.Get("canvas").As<Control>();
        if(first)
        {
            plan=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_plan.gd").New().As<Control>();plan.Set("workspace",workspace);var parent=canvas.GetParent();int index=canvas.GetIndex();var wrapper=new VBoxContainer {SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,SizeFlagsVertical=Control.SizeFlags.ExpandFill};parent.RemoveChild(canvas);parent.AddChild(wrapper);parent.MoveChild(wrapper,index);var tools=new HFlowContainer();tools.AddThemeConstantOverride("h_separation",3);wrapper.AddChild(tools);var editor=plan;foreach(var entry in new[]{("Select","↖ Select"),("Wall","╱ Wall"),("Room","▱ Room"),("Door","▯ Door"),("Window","▦ Window"),("Arch","∩ Arch"),("Stairs","↗ Stairs"),("Delete","⌫")}){string tool=entry.Item1;var button=new Button {Text=entry.Item2,TooltipText=tool};tools.AddChild(button);button.Pressed+=()=>{editor.Call("cancel");editor.Set("tool",tool);editor.GrabFocus();};}var snap=new CheckButton {Text="Snap",ButtonPressed=true};tools.AddChild(snap);snap.Toggled+=on=>editor.Set("snap",on);var split=new HSplitContainer {SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,SizeFlagsVertical=Control.SizeFlags.ExpandFill};wrapper.AddChild(split);split.AddChild(editor);split.AddChild(canvas);split.SplitOffsets=new[]{-60};workspace.SetMeta("building_plan",editor);workspace.SetMeta("building_plan_tools",tools);Button(tools,"⌖ Fit",()=>frame(workspace));
        }
        string id=root.Get("id").AsString();if(plan!.Get("building_id").AsString()!=id){plan.Call("cancel");plan.Set("selected_wall",-1);plan.Set("selected_opening",-1);}plan.Set("building_id",id);var state=Get(Session(workspace).Get("document").As<Resource>().Get("workspace_state").AsGodotDictionary(),"architecture_plan",new Settings()).AsGodotDictionary();if(Get(state,"owner", "").AsString()==id){plan.Set("current_floor",Get(state,"floor",0));plan.Set("zoom",Get(state,"zoom",35.0));plan.Set("pan",Get(state,"pan",Vector2.Zero));plan.Set("cutaway",Get(state,"cutaway",false));}if(plan.GetParent() is HSplitContainer container)container.SplitOffsets=new[]{Get(state,"split",-60).AsInt32()};plan.Set("view_mode",mode);plan.Visible=mode!=2;canvas.Visible=mode!=0;workspace.GetMeta("building_plan_tools").As<Control>().Visible=mode!=2;return new Settings {["plan"]=plan,["frame"]=first&&mode!=0&&fitFirst};
    }
    public Resource? restore_now(Control workspace,Resource document,Settings state)
    {
        if(!GodotObject.IsInstanceValid(workspace)||!workspace.IsInsideTree()||Session(workspace).Get("document").As<Resource>()!=document)return null;var root=_documents.component(document,Get(state,"owner", "").AsString());if(_buildings.source(root)!=null){document.Get("workspace_state").AsGodotDictionary()["architecture_plan"]=state;return root;}if(workspace.HasMeta("building_plan")){var plan=workspace.GetMeta("building_plan").As<Control>();plan.Set("building_id", "");plan.Set("cutaway",false);plan.Hide();workspace.GetMeta("building_plan_tools").As<Control>().Hide();var canvas=workspace.Get("canvas").As<Control>();canvas.Show();canvas.Set("preview_hidden",new Settings());if(canvas.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/EnvironmentWorkspace/environment_viewport.gd")canvas.Get("renderer").As<Node3D>().Set("preview_hidden",new Settings());canvas.Call("request_sync");}return null;
    }
}
