using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingUiOperations : RefCounted
{
    private readonly BuildingSourceOperations _sources=new();
    private readonly BuildingModuleOperations _modules=new();
    private readonly ModelDocumentOperations _documents=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static RefCounted Session(Control workspace)=>workspace.Get("session").As<RefCounted>();
    private static BuildingEditOperations Edits()=>Engine.GetSingleton("KiwiNativeServices").Call("service","building_edit").As<BuildingEditOperations>();
    public Resource? source(Control workspace,string id)=>Edits().source(Session(workspace),id);
    private void Apply(Control workspace,string id,Resource source,string label){var job=new BuildingUiApplyJob();workspace.AddChild(job);job.start(workspace,id,source,label);}
    private static void Number(Node parent,string title,double value,double low,double high,double step,Action<double> setter)
    {var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=title,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var number=new DragNumber();number.MinValue=low;number.MaxValue=high;number.Step=step;number.CustomMinimumSize=new Vector2(85,0);number.SetValueNoSignal(value);row.AddChild(number);number.ValueChanged+=setter.Invoke;number.Connect("drag_committed",Callable.From<double>(setter));}
    private static Button Button(Node parent,string title,Action action){var button=new Button {Text=title};parent.AddChild(button);button.Pressed+=action;return button;}
    public void wall_properties(Control workspace,string id,Resource source,int level,int index,int selected,Node parent)
    {
        var floor=source.Get("floors").AsGodotArray()[level].AsGodotDictionary();var wall=floor["walls"].AsGodotArray()[index].AsGodotDictionary();parent.AddChild(new Label {Text="SELECTED WALL"});Settings Wall(Resource next)=>next.Get("floors").AsGodotArray()[level].AsGodotDictionary()["walls"].AsGodotArray()[index].AsGodotDictionary();Settings Opening(Resource next)=>Wall(next)["openings"].AsGodotArray()[selected].AsGodotDictionary();
        Number(parent,"Wall height",_sources.wall_height(source,floor,wall),.1,20,.05,value=>{var next=_sources.copy(this.source(workspace,id)!);var entry=Wall(next);entry["height"]=value;entry["height_mode"]="custom";Apply(workspace,id,next,"Change wall height");});var openings=Get(wall,"openings",new GArray()).AsGodotArray();if(selected<0||selected>=openings.Count)return;var opening=openings[selected].AsGodotDictionary();parent.AddChild(new Label {Text=Get(opening,"type","Opening").AsString().Capitalize()});var types=new[]{"door","slider","window","arch"};var type=new OptionButton();parent.AddChild(type);foreach(string name in new[]{"Hinged door","Sliding door","Window","Arch"})type.AddItem(name);type.Select(Math.Max(0,Array.IndexOf(types,Get(opening,"type","door").AsString())));type.ItemSelected+=choice=>{var next=_sources.copy(this.source(workspace,id)!);var entry=Opening(next);entry["type"]=types[choice];entry["bottom"]=choice==2?1.0:0.0;entry["height"]=choice==2?1.2:Math.Max(2.1,Get(entry,"height",2.1).AsDouble());Apply(workspace,id,next,"Change opening type");};
        foreach(var spec in new[]{("Width","width",.1,10.0),("Height","height",.1,10.0),("Sill height","bottom",0.0,10.0),("Position along wall","t",0.0,1.0),("Door angle","angle",-170.0,170.0),("Slide amount","slide",0.0,1.0)}){string key=spec.Item2,kind=Get(opening,"type", "").AsString();if((key=="angle"&&kind!="door")||(key=="slide"&&kind!="slider"))continue;Number(parent,spec.Item1,Get(opening,key,0.0).AsDouble(),spec.Item3,spec.Item4,.01,value=>{var next=_sources.copy(this.source(workspace,id)!);Opening(next)[key]=value;Apply(workspace,id,next,"Edit opening");});}Button(parent,"Remove opening",()=>{var next=_sources.copy(this.source(workspace,id)!);Wall(next)["openings"].AsGodotArray().RemoveAt(selected);Apply(workspace,id,next,"Remove opening");});
    }
    public void stair_properties(Control workspace,string id,Resource source,int index,Node parent)
    {
        var stair=source.Get("stairs").AsGodotArray()[index].AsGodotDictionary();Settings Stair(Resource next)=>next.Get("stairs").AsGodotArray()[index].AsGodotDictionary();var kind=new OptionButton();parent.AddChild(kind);foreach(string name in new[]{"Straight staircase","L staircase","U staircase","Spiral staircase"})kind.AddItem(name);kind.Select(Get(stair,"type",0).AsInt32());kind.ItemSelected+=value=>{var next=_sources.copy(this.source(workspace,id)!);Stair(next)["type"]=value;Apply(workspace,id,next,"Change staircase");};foreach(var spec in new[]{("Width","width",.3,5.0),("Run","length",.5,20.0),("Steps","steps",2.0,80.0),("Rotation","yaw",-180.0,180.0)}){string key=spec.Item2;Number(parent,spec.Item1,Get(stair,key,key=="steps"?16.0:0.0).AsDouble(),spec.Item3,spec.Item4,key=="steps"?1:.05,value=>{var next=_sources.copy(this.source(workspace,id)!);Stair(next)[key]=value;Apply(workspace,id,next,"Edit staircase");});}for(int axis=0;axis<2;axis++){int component=axis;Number(parent,"Stair "+new[]{"X","Z"}[axis],Get(stair,"position",Vector2.Zero).AsVector2()[axis],-100,100,.1,value=>{var next=_sources.copy(this.source(workspace,id)!);var entry=Stair(next);var point=Get(entry,"position",Vector2.Zero).AsVector2();point[component]=(float)value;entry["position"]=point;Apply(workspace,id,next,"Move staircase");});}Button(parent,"Remove staircase",()=>{var next=_sources.copy(this.source(workspace,id)!);next.Get("stairs").AsGodotArray().RemoveAt(index);Apply(workspace,id,next,"Remove staircase");});
    }
}
