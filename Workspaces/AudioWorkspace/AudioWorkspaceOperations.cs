using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations:RefCounted
{
    private static T Field<T>(GodotObject o,string key) where T:GodotObject=>(T)o.Get(key).AsGodotObject();
    private static Settings Dict(GodotObject o,string key)=>o.Get(key).AsGodotDictionary();
    private static GArray Items(GodotObject o,string key)=>o.Get(key).AsGodotArray();
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    public StyleBoxFlat box(Color fill,Color border,int radius){var style=new StyleBoxFlat{BgColor=fill,BorderColor=border,ContentMarginLeft=8,ContentMarginRight=8,ContentMarginTop=5,ContentMarginBottom=5};style.SetCornerRadiusAll(radius);style.SetBorderWidthAll(1);return style;}
    public void theme(Control o)
    {
        var ui=new Theme{DefaultFontSize=12};o.Theme=ui;foreach(string type in new[]{"Button","OptionButton","MenuButton"}){ui.SetStylebox("normal",type,box(new Color("20303c"),new Color("3c5668"),5));ui.SetStylebox("hover",type,box(new Color("2b4c4b"),new Color("6cdcc0"),5));ui.SetStylebox("pressed",type,box(new Color("2c6254"),new Color("77e4c3"),5));}ui.SetStylebox("panel","PanelContainer",box(new Color("14202b"),new Color("334a5c"),5));ui.SetStylebox("normal","LineEdit",box(new Color("111c26"),new Color("405b70"),4));ui.SetStylebox("panel","TabContainer",box(new Color("14212d"),new Color("3e5669"),5));ui.SetColor("font_color","Label",new Color("dbe7f0"));
    }
    public Button button(Control o,Node parent,string text,Variant callback,string tooltip){var button=new Button{Text=text,TooltipText=tooltip};o.Call("_connect_control",button,"pressed",callback);parent.AddChild(button);return button;}
    public Label label(Node parent,string text){var label=new Label{Text=text,AutowrapMode=parent is HFlowContainer or HBoxContainer?TextServer.AutowrapMode.Off:TextServer.AutowrapMode.WordSmart};parent.AddChild(label);return label;}
    public void clear(Node parent){foreach(var child in parent.GetChildren()){parent.RemoveChild(child);child.QueueFree();}}
    public void heading(Node parent,string text){var caption=label(parent,text.ToUpperInvariant());caption.AddThemeColorOverride("font_color",new Color("7bdfc6"));caption.AddThemeFontSizeOverride("font_size",11);}
    public SpinBox number(Control o,Node parent,string text,double value,double minimum,double maximum,double step,Variant callback,bool liveContext)
    {
        var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label{Text=text,CustomMinimumSize=new Vector2(104,0)});var number=new SpinBox{MinValue=minimum,MaxValue=maximum,Step=step,Value=value,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};row.AddChild(number);var owner=Field<RefCounted>(o,"session");var document=owner.Get("document").AsGodotObject();long generation=o.Get("_controls_generation").AsInt64();number.ValueChanged+=next=>{if(!number.IsInsideTree()||number.IsQueuedForDeletion())return;if(!liveContext&&(Field<RefCounted>(o,"session")!=owner||owner.Get("document").AsGodotObject()!=document||generation!=o.Get("_controls_generation").AsInt64()))return;var previous=o.Get("_edit_control_id");o.Set("_edit_control_id",number.GetInstanceId());try{o.Call("_invoke_value",callback,next);}finally{o.Set("_edit_control_id",previous);}};return number;
    }
    public CheckBox check(Control o,Node parent,string text,bool value,Variant callback){var button=new CheckBox{Text=text,ButtonPressed=value};o.Call("_connect_control",button,"toggled",callback);parent.AddChild(button);return button;}
    public OptionButton choice(Control o,Node parent,string text,GArray items,string current,Variant callback)
    {
        var row=new HBoxContainer();parent.AddChild(row);if(text.Length>0)row.AddChild(new Label{Text=text,CustomMinimumSize=new Vector2(86,0)});var choice=new OptionButton{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};row.AddChild(choice);foreach(var item in items){string value=item.AsString();choice.AddItem(value);if(value==current)choice.Select(choice.ItemCount-1);}choice.ItemSelected+=index=>o.Call("_invoke_value",callback,items[(int)index].AsString());return choice;
    }
    public void edit(Control o,string label,Variant callback)
    {
        if(o.Get("_syncing").AsBool())return;o.Call("_finish_automation_pass","Another parameter edit ended the pass");var session=Field<RefCounted>(o,"session");var gesture=Field<RefCounted>(o,"_parameter_gesture");if(!gesture.Call("valid",session).AsBool()||o.Get("_parameter_control_id").AsInt64()!=o.Get("_edit_control_id").AsInt64()){commit_parameter_edit(o);gesture.Call("begin",session,label);o.Set("_parameter_control_id",o.Get("_edit_control_id"));}o.Call("_invoke_action",callback);session.Call("preview");Field<Timer>(o,"_edit_timer").Start();
    }
    public void commit_parameter_edit(Control o){Field<Timer>(o,"_edit_timer").Stop();o.Set("_parameter_control_id",0);Field<RefCounted>(o,"_parameter_gesture").Call("finish",Field<RefCounted>(o,"session"),true);}
    public void discard_parameter_handle(Control o){Field<Timer>(o,"_edit_timer").Stop();o.Set("_parameter_control_id",0);Field<RefCounted>(o,"_parameter_gesture").Call("clear");}
    public void finish_control_edits(Control o){commit_parameter_edit(o);foreach(var raw in Items(o,"_mixer_gestures"))finish_mixer_gesture(o,raw.AsGodotDictionary(),true);foreach(string field in new[]{"canvas","piano","steps"})Field<Control>(o,field).Call("finish_edit",true);Field<Control>(o,"canvas").Call("finish_automation_edit",true);o.Set("_interaction_epoch",o.Get("_interaction_epoch").AsInt64()+1);}
    public bool mixer_context_current(Control o,Control control,RefCounted owner,RefCounted document)=>control.IsInsideTree()&&!control.IsQueuedForDeletion()&&Field<RefCounted>(o,"session")==owner&&owner.Get("document").AsGodotObject()==document;
    public void finish_mixer_gesture(Control o,Settings state,bool keep)
    {
        bool held=state["held"].AsBool();state["held"]=false;if(held)state["blocked"]=true;if(!held)return;if(state["automation"].AsBool()){if(state["epoch"].AsInt64()==o.Get("_interaction_epoch").AsInt64()){if(keep)o.Call("_automation_gesture_end");else{o.Set("_interaction_epoch",o.Get("_interaction_epoch").AsInt64()+1);Field<RefCounted>(o,"automation_recording").Call("discard","Read: gesture cancelled.");}}}else state["gesture"].AsGodotObject().Call("finish",Field<RefCounted>(o,"session"),keep&&state["changed"].AsBool());
    }
    public Settings window(Control o,string title,Vector2I dimensions)
    {
        var window=new Window{Title=title,Size=dimensions,MinSize=new Vector2I(360,180)};o.AddChild(window);var margin=new MarginContainer();margin.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);foreach(string side in new[]{"left","right","top","bottom"})margin.AddThemeConstantOverride("margin_"+side,12);window.AddChild(margin);var host=new VBoxContainer();host.AddThemeConstantOverride("separation",8);margin.AddChild(host);window.CloseRequested+=window.QueueFree;window.PopupCentered();return new Settings{["window"]=window,["host"]=host};
    }
    public void name_dialog(Control o,string title,string suggested,Variant callback,bool allowEmpty)
    {
        var dialog=window(o,title,new Vector2I(430,150));var host=dialog["host"].As<Node>();var windowNode=dialog["window"].As<Window>();var edit=new LineEdit{Text=suggested};host.AddChild(edit);var save=new Button{Text="Save"};host.AddChild(save);save.Pressed+=()=>{if(allowEmpty||edit.Text.Trim().Length>0){o.Call("_invoke_value",callback,edit.Text.Trim());windowNode.QueueFree();}};edit.GrabFocus();edit.SelectAll();
    }
}
