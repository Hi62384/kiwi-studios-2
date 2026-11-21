using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class RigUiToolbar : RefCounted
{
    internal static Control Canvas(Control workspace)=>workspace.Get("canvas").As<Control>();
    internal static RigEditor Editor(Control workspace)=>Canvas(workspace).Get("rig_tool").As<RefCounted>().Get("editor").As<RefCounted>().Get("_native").As<RigEditor>();
    internal static Button Button(Node parent,string title,Action action,string hint="")
    {var button=new Button {Text=title,TooltipText=hint,CustomMinimumSize=new Vector2(0,28)};parent.AddChild(button);button.Pressed+=action;return button;}
    internal static void Label(Node parent,string title)
    {var label=new Label{Text=title};label.AddThemeColorOverride("font_color",new Color("7ddcc4"));parent.AddChild(label);}
    internal static OptionButton Choice(Node parent,string[] options,string current,Action<string> changed)
    {var input=new OptionButton{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,ClipText=true};foreach(string title in options) input.AddItem(title);input.Select(Math.Max(0,Array.IndexOf(options,current)));parent.AddChild(input);input.ItemSelected+=index=>changed(input.GetItemText((int)index));return input;}
    internal static CheckButton Toggle(Node parent,string title,bool enabled,Action<bool> changed)
    {var control=new CheckButton{Text=title,ButtonPressed=enabled};parent.AddChild(control);control.Toggled+=value=>changed(value);return control;}
    public void refresh(Control workspace) {workspace.Set("_refresh_pending",true);Canvas(workspace).Call("request_sync");}
    public void set_mode(Control workspace,string value)
    {
        var canvas=Canvas(workspace);canvas.Get("rig_tool").As<RefCounted>().Call("finish",true);var editor=Editor(workspace);editor.mode=value;editor.enabled=true;
        if(value=="Draw"&&editor.rig()==null) editor.empty_rig();if(value=="Pose") canvas.Set("tool","Rotate");refresh(workspace);canvas.GrabFocus();
    }
    public void quick_rig(Control workspace,RefCounted state)
    {
        var popup=new PopupPanel{Name="QuickRig"};workspace.AddChild(popup);var column=new VBoxContainer{CustomMinimumSize=new Vector2(340,180)};popup.AddChild(column);Label(column,"QUICK RIG   /   Create → Bind → Pose");
        Button(column,"✦ Auto Rig · fitted chain",()=>{Editor(workspace).create("Flexible chain",state.Get("chain_count").AsInt32());popup.Hide();refresh(workspace);},"Fits an editable chain to the longest bounding-box axis. No anatomy recognition is claimed.");
        Button(column,"◇ Choose rig template…",()=>{popup.Hide();templates(workspace,state);});
        Button(column,"✎ Draw bones in viewport",()=>{popup.Hide();set_mode(workspace,"Draw");});
        Button(column,"↳ Attach existing rig",()=>{popup.Hide();Editor(workspace).enabled=true;refresh(workspace);},"Choose the rig in the inspector, then bind the selected meshes.");
        popup.PopupHide+=popup.QueueFree;popup.PopupCentered(new Vector2I(370,230));
    }
    public void templates(Control workspace,RefCounted state)
    {
        var popup=new PopupPanel{Name="RigTemplates"};workspace.AddChild(popup);var column=new VBoxContainer{CustomMinimumSize=new Vector2(350,350)};popup.AddChild(column);Label(column,"RIG TEMPLATES · approximate fitting");
        var count=new SpinBox{MinValue=1,MaxValue=64,Value=state.Get("chain_count").AsInt32(),Prefix="Chain joints "};column.AddChild(count);
        var scroll=new ScrollContainer{CustomMinimumSize=new Vector2(0,290)};column.AddChild(scroll);var list=new VBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};scroll.AddChild(list);
        foreach(var category in RigTemplates.Categories)
        {Label(list,category.Key.ToUpperInvariant());foreach(string kind in category.Value) Button(list,kind,()=>{state.Set("chain_count",(int)count.Value);Editor(workspace).create(kind,(int)count.Value);popup.Hide();refresh(workspace);});}
        popup.PopupHide+=popup.QueueFree;popup.PopupCentered(new Vector2I(390,440));
    }
    public void more_menu(Control workspace,RefCounted state)
    {
        string[] options={"Extrude connected bone","Select parent bone","Select first child","Disconnect joint","Connect to parent","Insert joint","Duplicate chain","Mirror chain","Unparent bone","Delete bone","Reset entire pose","Save rig preset","Load rig preset","Detach selected meshes","Leave rigging"};
        workspace.Call("_choice_menu","RIG OPERATIONS",new Godot.Collections.Array(options.Select(value=>Variant.From(value))),Callable.From<string>(value=>
        {
            var editor=Editor(workspace);var armature=editor.rig();var bones=armature?.Get("bones").AsGodotArray();
            switch(value)
            {
                case "Extrude connected bone":
                    if(bones!=null&&bones.Count>0){set_mode(workspace,"Draw");var tool=Canvas(workspace).Get("rig_tool").As<RefCounted>().Get("_native").As<RigViewport>();tool.chain_parent=editor.selected_bone;tool.chain=new RigMath().tail(bones[tool.chain_parent].AsGodotDictionary(),tool.world_bones()[tool.chain_parent]);}break;
                case "Select parent bone": if(bones!=null&&bones.Count>0) editor.selected_bone=Math.Max(0,bones[editor.selected_bone].AsGodotDictionary()["parent"].AsInt32());break;
                case "Select first child": if(bones!=null) for(int i=0;i<bones.Count;i++) if(bones[i].AsGodotDictionary()["parent"].AsInt32()==editor.selected_bone){editor.selected_bone=i;break;}break;
                case "Disconnect joint": if(bones!=null&&bones.Count>0){var session=workspace.Get("session").As<RefCounted>();session.Call("begin");bones[editor.selected_bone].AsGodotDictionary()["connected"]=false;session.Call("commit","Disconnect joint");}break;
                case "Connect to parent": if(bones!=null&&bones.Count>0) editor.parent(bones[editor.selected_bone].AsGodotDictionary()["parent"].AsInt32(),true);break;
                case "Insert joint": editor.insert_joint();break;
                case "Duplicate chain": editor.duplicate_chain(false);break;
                case "Mirror chain": editor.duplicate_chain(true);break;
                case "Unparent bone": editor.parent(-1,false);break;
                case "Delete bone": editor.delete_bone();break;
                case "Reset entire pose": editor.reset_pose(true);break;
                case "Save rig preset": state.Call("save_preset");break;
                case "Load rig preset": state.Call("load_preset");break;
                case "Detach selected meshes": editor.detach();break;
                case "Leave rigging": editor.enabled=false;break;
            }
            refresh(workspace);
        }));
    }
    public void build_context(Control workspace,RefCounted state,HBoxContainer parent)
    {
        string[] modes={"Draw","Edit","Pose","Weight","Envelope"},titles={"✎ Draw","◇ Edit","↻ Pose","◉ Weight","◯ Envelope"};var editor=Editor(workspace);
        for(int i=0;i<modes.Length;i++){string mode=modes[i];var control=Button(parent,titles[i],()=>set_mode(workspace,mode));control.ToggleMode=true;control.ButtonPressed=editor.mode==mode;}
        Button(parent,"↳ Bind",()=>state.Call("bind_async",state.Get("method")),"Bind selected mesh components without joining them");
        var input=Choice(parent,new[]{"Smooth","Distance","Envelope","Rigid"},state.Get("method").AsString(),value=>state.Set("method",value));input.CustomMinimumSize=new Vector2(110,0);
        Button(parent,"⋯",()=>state.Call("more_menu"));
        if(editor.busy) Button(parent,"Cancel weighting",()=>{var job=state.Get("job").As<RigWeightJob>();job?.cancel();});
    }
}
