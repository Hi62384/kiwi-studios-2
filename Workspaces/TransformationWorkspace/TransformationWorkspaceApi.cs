using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;

public partial class TransformationWorkspaceOperations
{
    private static void Dispatch(Control owner,GodotObject binding,params Variant[] arguments){var values=new GArray();foreach(var value in arguments)values.Add(value);owner.Call("_dispatch_native_callback",binding,values);}
    public Button button(Control owner,Node parent,string text,Variant callback,string hint){var result=Attach(parent,new Button {Text=text,TooltipText=hint,CustomMinimumSize=new Vector2(0,28)});result.SetMeta("native_callback",callback);result.Pressed+=()=>Dispatch(owner,result);return result;}
    public Label label(Node parent,string text)=>Caption(parent,text);
    public void clear(Node parent)=>Clear(parent);
    public OptionButton choice(Control owner,Node parent,GArray options,string current,Variant callback){var titles=new List<string>();foreach(var value in options)titles.Add(value.AsString());OptionButton? result=null;result=Choice(parent,titles,current,value=>Dispatch(owner,result!,value));result.SetMeta("native_callback",callback);return result;}
    public Godot.Range number(Control owner,Node parent,string caption,double value,double minimum,double maximum,double step,Variant setter,bool stateEdit,bool undoable){Godot.Range? number=null;number=NumberControl(owner,parent,caption,value,minimum,maximum,step,next=>Dispatch(owner,number!,next),stateEdit,undoable);number.SetMeta("native_callback",setter);return number;}
    public void menu(Control owner,string title,GArray options,Variant callback){var popup=Attach(owner,new PopupPanel());popup.SetMeta("native_callback",callback);var list=Attach(popup,new VBoxContainer {CustomMinimumSize=new Vector2(260,0)});Caption(list,title);foreach(var raw in options){string option=raw.AsString();Action(list,option,()=>{popup.Hide();Dispatch(owner,popup,option);});}popup.PopupHide+=()=>popup.QueueFree();popup.PopupCentered();}
    public void change_keys(Control owner,string title,Variant callback){using var binding=new RefCounted();binding.SetMeta("native_callback",callback);ChangeKeys(owner,title,(item,key)=>Dispatch(owner,binding,item,key));}
    public void open_example(Control owner,string title){using var examples=new TransformationExamples();var document=examples.create(title);var tabs=owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs");if(tabs!=null)tabs.Call("open_transformation",document);else if(!Session(owner).Get("dirty").AsBool())open_source(owner,document,new Godot.Collections.Dictionary());else{var popup=Attach(owner,new ConfirmationDialog {Title="Open example",DialogText="Replace this unsaved document?"});popup.Confirmed+=()=>{open_source(owner,document,new Godot.Collections.Dictionary());popup.QueueFree();};popup.Canceled+=()=>popup.QueueFree();popup.PopupCentered(new Vector2I(360,130));}}
    public void examples_menu(Control owner)=>Menu(owner,"WORKED EXAMPLES",new[]{"Blinking eye","Talking mouth","Bouncing ball","Layered face","Bleeding cut"},title=>open_example(owner,title));
    public void draw(Control owner)=>owner.DrawRect(new Rect2(Vector2.Zero,owner.Size),new Color("0f1c26"));
}
