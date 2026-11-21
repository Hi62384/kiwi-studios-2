using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldUiOperations
{
    private void WorldSettings(Control owner,Resource item,Resource source,Node parent,Settings catalog)
    {
        string id=item.Get("id").AsString();var recipes=new MenuButton {Text="Generate world preset…",Disabled=!new WorldRecipeOperations().empty(source)||source.Get("owned_terrain_id").AsString().Length==0||source.Get("owned_terrain_id").AsString()!=source.Get("terrain_id").AsString(),TooltipText="Start from an empty world with owned terrain. Existing authored worlds and external terrain are preserved."};parent.AddChild(recipes);var recipeNames=catalog["recipes"].AsStringArray();foreach(string name in recipeNames)recipes.GetPopup().AddItem(name);recipes.GetPopup().IdPressed+=index=>{if(Fresh(recipes,owner))GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").Call("request",owner,id,recipeNames[index]);};
        Value(owner,parent,"World layout seed",source.Get("seed").AsDouble(),-1000000,1000000,1,value=>{var current=Source(owner,id);if(current!=null)Apply(owner,id,new WorldSeedOperations().apply(current,(long)value),"Change world layout seed");});Value(owner,parent,"Render distance (0 = all)",source.Get("render_distance").AsDouble(),0,100000,10,value=>Modify(owner,id,next=>next.Set("render_distance",value),"Change world render distance"));
        foreach(var spec in new[]{("Building plot budget","max_building_plots",1.0,8192.0,1.0),("Eager building detail","eager_building_limit",0.0,512.0,1.0),("Building detail distance","building_detail_distance",10.0,10000.0,10.0),("Detailed buildings per view","max_active_buildings",1.0,512.0,1.0),("Building cache (MB)","building_cache_mb",16.0,1024.0,16.0)})Value(owner,parent,spec.Item1,source.Get(spec.Item2).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>Modify(owner,id,next=>next.Set(spec.Item2,spec.Item2=="building_detail_distance"?Variant.From(value):Variant.From((int)value)),"Change building detail budget"));
        Toggle(owner,parent,"Avoid existing structures",source.Get("respect_existing_objects").AsBool(),on=>Modify(owner,id,next=>next.Set("respect_existing_objects",on),"Change existing-object placement masks"));Toggle(owner,parent,"Live terrain and object updates",source.Get("auto_update_dependencies").AsBool(),on=>Modify(owner,id,next=>next.Set("auto_update_dependencies",on),"Toggle live world updates"));
        foreach(int axis in new[]{0,1})Value(owner,parent,axis==0?"World width":"World depth",source.Get("dimensions").AsVector2()[axis],16,16384,16,value=>Modify(owner,id,next=>{var dimensions=next.Get("dimensions").AsVector2();dimensions[axis]=(float)value;next.Set("dimensions",dimensions);new WorldSourceOperations().configure_regions(next);},"Resize world"));Value(owner,parent,"Region size",source.Get("region_size").AsDouble(),16,4096,16,value=>Modify(owner,id,next=>{next.Set("region_size",value);new WorldSourceOperations().configure_regions(next);},"Resize world regions"));
        var labels=new List<string>{"Terrain · None"};var ids=new List<string>{""};var session=Session(owner);var environment=session.Call("environment").As<Resource>();foreach(var value in session.Get("document").As<Resource>().Get("components").AsGodotArray()){var component=value.As<Resource>();if(environment.Call("terrain",component.Get("id")).AsGodotObject()==null)continue;ids.Add(component.Get("id").AsString());labels.Add(component.Get("title").AsString());}Choice(owner,parent,labels.ToArray(),Math.Max(0,ids.IndexOf(source.Get("terrain_id").AsString())),index=>Modify(owner,id,next=>next.Set("terrain_id",ids[index]),"Choose world terrain"));
        var grading=new HBoxContainer();parent.AddChild(grading);Button(owner,grading,"Grade roadbeds",()=>grade(owner,id,false));Button(owner,grading,"Remove grading",()=>grade(owner,id,true));if(source.Get("roads").AsGodotArray().Any(value=>Get(value.AsGodotDictionary(),"mode","Ground").AsString()=="Tunnel"))Button(owner,parent,"↻ Refresh tunnel terrain",()=>{var current=Source(owner,id);if(current!=null)Apply(owner,id,current,"Refresh tunnel excavation");});
    }
    private void Regions(Control owner,string id,Resource source,Node parent)
    {
        var regions=source.Get("regions").AsGodotArray();int index=Math.Clamp(owner.GetMeta("world_region_index",0).AsInt32(),0,Math.Max(0,regions.Count-1));var choice=Choice(owner,parent,regions.Select(value=>value.AsGodotDictionary()["name"].AsString()).ToArray(),index,next=>owner.SetMeta("world_region_index",next));var row=new HBoxContainer();parent.AddChild(row);
        foreach(string field in new[]{"enabled","locked"})
        {
            var box=Toggle(owner,row,field=="enabled"?"Enabled":"Locked",regions.Count>0&&Get(regions[index].AsGodotDictionary(),field,false).AsBool(),on=>ModifyEntry(owner,id,"regions",choice.Selected,next=>next[field]=on,"Change world region"));box.Disabled=regions.Count==0;choice.ItemSelected+=next=>{if(!Fresh(box,owner))return;var current=Source(owner,id);if(current==null)return;var entries=current.Get("regions").AsGodotArray();if(next>=0&&next<entries.Count)box.SetPressedNoSignal(Get(entries[(int)next].AsGodotDictionary(),field,false).AsBool());};
        }
    }
}
