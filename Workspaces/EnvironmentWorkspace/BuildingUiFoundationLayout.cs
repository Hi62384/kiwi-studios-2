using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingUiOperations
{
    private readonly BuildingFoundationOperations _foundation=new();
    private readonly BuildingLayoutOperations _layouts=new();
    private static SpinBox NumberInput(double low,double high,double step,double value)
    {var number=new DragNumber();number.MinValue=low;number.MaxValue=high;number.Step=step;number.SetValueNoSignal(value);return number;}
    private static void NumberRow(Node parent,string title,SpinBox number)
    {var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=title,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});row.AddChild(number);}
    private void FoundationProperties(Control workspace,Resource root,Node parent)
    {
        string id=root.Get("id").AsString();var terrainIds=new List<string>();var terrains=new OptionButton();parent.AddChild(terrains);var document=Session(workspace).Get("document").As<Resource>();foreach(var value in document.Get("components").AsGodotArray()){var component=value.As<Resource>();string componentId=component.Get("id").AsString();if(document.Call("terrain",componentId).As<Resource>()==null)continue;terrainIds.Add(componentId);terrains.AddItem("Foundation terrain · "+component.Get("title").AsString());}if(terrainIds.Count==0){terrains.AddItem("Add terrain to enable foundation shaping");terrains.Disabled=true;}var blend=NumberInput(0,20,.1,1);blend.CustomMinimumSize=new Vector2(90,0);NumberRow(parent,"Foundation blend distance",blend);void Restore(long index){if(index<0||index>=terrainIds.Count)return;var current=Session(workspace).Get("document").As<Resource>().Call("terrain",terrainIds[(int)index]).As<Resource>();blend.SetValueNoSignal(1);if(current==null)return;var generation=current.Get("generation").As<Resource>();if(generation==null)return;foreach(var value in generation.Get("layers").AsGodotArray()){var layer=value.AsGodotDictionary();if(Get(layer,"foundation_owner", "").AsString()!=id)continue;blend.SetValueNoSignal(Get(layer,"feather",1.0).AsDouble());break;}}terrains.ItemSelected+=Restore;Restore(0);var actions=new HBoxContainer();parent.AddChild(actions);foreach(var entry in new[]{("Update foundation",false),("Remove",true)}){bool remove=entry.Item2;Button(actions,entry.Item1,()=>{int index=terrains.Selected;if(index<0||index>=terrainIds.Count)return;string error=_foundation.set_modifier(Session(workspace),id,terrainIds[index],blend.Value,remove);Status(workspace,error.Length>0?error:"Foundation terrain modifier updated; sculpt edits are preserved");});}
    }
    private void LayoutProperties(Control workspace,Resource root,Resource source,Node parent)
    {
        string id=root.Get("id").AsString();var layout=new VBoxContainer();parent.AddChild(layout);layout.AddChild(new Label {Text="RECTANGULAR ROOM LAYOUT"});var rooms=NumberInput(2,12,1,5);NumberRow(layout,"Rooms per level",rooms);var corridor=NumberInput(.9,3,.05,1.2);NumberRow(layout,"Hallway width",corridor);Number(layout,"Layout seed",source.Get("seed").AsDouble(),0,100000,1,value=>{var next=_sources.copy(this.source(workspace,id)!);next.Set("seed",(int)value);Apply(workspace,id,next,"Change layout seed");});Button(layout,"▦ Generate rooms and doors",()=>{var result=_layouts.generate(this.source(workspace,id)!,(int)rooms.Value,corridor.Value,Array.Empty<string>(),Array.Empty<float>());var errors=result["errors"].AsStringArray();if(errors.Length>0){Status(workspace,errors[0]);return;}Apply(workspace,id,result["source"].As<Resource>(),"Generate room layout");});
    }
}
