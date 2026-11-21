using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldUiOperations : RefCounted
{
    private static readonly string[] StateKeys={"world_section","world_road_index","world_settlement_index","world_region_index","world_forest_index","world_prop_index","world_connection_index","world_district_index","world_block_index"};
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    internal static RefCounted Session(Control owner)=>owner.Get("session").As<RefCounted>();
    internal static Resource? Source(Control owner,string id)=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").Call("source",Session(owner),id).As<Resource>();
    private static bool Fresh(Node node,Control owner)
    {if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree()||!GodotObject.IsInstanceValid(node)||!node.IsInsideTree())return false;for(Node? current=node;current!=null;current=current.GetParent())if(current.IsQueuedForDeletion())return false;return true;}
    private static void Value(Control owner,Node parent,string title,double value,double minimum,double maximum,double step,Action<double> changed)
    {owner.Call("_value",parent,title,value,minimum,maximum,step,Callable.From<double>(next=>{if(Fresh(parent,owner))changed(next);}));}
    private static Button Button(Control owner,Node parent,string text,Action pressed)
    {var button=new Button {Text=text};parent.AddChild(button);button.Pressed+=()=>{if(Fresh(button,owner))pressed();};return button;}
    private static CheckButton Toggle(Control owner,Node parent,string text,bool value,Action<bool> changed)
    {var button=new CheckButton {Text=text,ButtonPressed=value};parent.AddChild(button);button.Toggled+=next=>{if(Fresh(button,owner))changed(next);};return button;}
    private static OptionButton Choice(Control owner,Node parent,string[] labels,int selected,Action<int> changed)
    {var choice=new OptionButton();parent.AddChild(choice);foreach(string label in labels)choice.AddItem(label);choice.Select(labels.Length>0?Math.Clamp(selected,0,labels.Length-1):-1);choice.ItemSelected+=next=>{if(Fresh(choice,owner))changed((int)next);};return choice;}
    private static void Modify(Control owner,string id,Action<Resource> changed,string label)
    {var source=Source(owner,id);if(source==null)return;var desired=new WorldSourceOperations().copy(source);changed(desired);Apply(owner,id,desired,label);}
    private static void Apply(Control owner,string id,Resource source,string label)
    {var job=new WorldUiActionJob();owner.AddChild(job);job.start(owner,"apply",id,source,label);}
    public void apply(Control owner,string id,Resource authored,string label)=>Apply(owner,id,authored,label);
    public void grade(Control owner,string id,bool remove)
    {var job=new WorldUiActionJob();owner.AddChild(job);job.start(owner,"grade",id,remove,"");}
    public void add_props(Control owner,string id,string mode)
    {var job=new WorldUiActionJob();owner.AddChild(job);job.start(owner,"props",id,mode,"");}
    public Settings capture(Control owner)
    {var result=new Settings();foreach(string key in StateKeys)result[key]=owner.GetMeta(key,0).AsInt64();return result;}
    public void restore(Control owner,Settings state)
    {foreach(string key in StateKeys)owner.SetMeta(key,Get(state,key,0).AsInt64());}
    public void compact_choices(Node parent)
    {foreach(var child in parent.GetChildren()){if(child is OptionButton choice){choice.FitToLongestItem=false;choice.ClipText=true;choice.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;}compact_choices(child);}}
}
