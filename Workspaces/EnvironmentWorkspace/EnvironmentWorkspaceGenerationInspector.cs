using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWorkspaceOperations
{
    private readonly TerrainGenerationOperations _generation=new();
    private static readonly string[] Profiles={"Flat","Rolling Hills","Mountainous","Island","Archipelago","Desert","Canyon","Plateau","Coastal","Custom"};
    private static readonly string[] Landforms={"Mountain range","Mountain","Ridge","Valley","Canyon","Cliff","Plateau","Mesa","Hill","Basin","Crater","Dunes"};
    private void EditGeneration(Control owner,string id,Action<Resource> edit)
    {var terrain=_documents.terrain(Document(Session(owner)),id);if(terrain==null)return;var source=terrain.Get("generation").As<Resource>();var next=source?.Duplicate(true)??_generation.preset(9);edit(next);regenerate_terrain(owner,id,new Settings {["generation"]=next},false,false);}
    public void edit_generation(Control owner,string id,Settings edit)=>EditGeneration(owner,id,next=>owner.Call("_invoke_source_edit",edit,next));
    private void EditErosion(Control owner,string id,Action<GArray> edit)
    {var terrain=_documents.terrain(Document(Session(owner)),id);if(terrain==null)return;var originals=terrain.Get("erosion").AsGodotArray();var next=originals.Duplicate();next.Clear();foreach(var operation in originals)next.Add(operation.As<Resource>().Duplicate(true));edit(next);regenerate_terrain(owner,id,new Settings {["erosion"]=next},false,false);}
    public void edit_erosion(Control owner,string id,Settings edit)=>EditErosion(owner,id,next=>owner.Call("_invoke_source_edit",edit,next));
    private static void Move(GArray items,int index,int direction){int target=Math.Clamp(index+direction,0,items.Count-1);var moving=items[index];items.RemoveAt(index);items.Insert(target,moving);}
    private static void Toggle(Node parent,string title,bool value,Action<bool> write)
    {var button=new CheckButton {Text=title,ButtonPressed=value};parent.AddChild(button);button.Toggled+=enabled=>write(enabled);}
    private void ExpandButton(Control owner,Node parent,string title,string id)
    {Button(parent,title,()=>{var expanded=State(owner,"_expanded_landforms");expanded[id]=!Get(expanded,id,false).AsBool();refresh_properties(owner);});}
    public void erosion_properties(Control owner,Resource item,Resource terrain)
    {
        string id=item.Get("id").AsString();var parent=Field<VBoxContainer>(owner,"properties");Menu(parent,"＋ Erosion operation ▾",new[]{"Hydraulic · water & sediment","Thermal · gravity & talus"},mode=>{var operation=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").New().As<Resource>();operation.Set("mode",mode);State(owner,"_expanded_landforms")[operation.Get("operation_id")]=true;EditErosion(owner,id,next=>next.Add(operation));});var operations=terrain.Get("erosion").AsGodotArray();
        for(int index=0;index<operations.Count;index++)
        {
            int slot=index;var operation=operations[index].As<Resource>();string operationId=operation.Get("operation_id").AsString();var row=new HBoxContainer();parent.AddChild(row);var enabled=new CheckBox {ButtonPressed=operation.Get("enabled").AsBool()};row.AddChild(enabled);enabled.Toggled+=value=>EditErosion(owner,id,next=>next[slot].As<Resource>().Set("enabled",value));ExpandButton(owner,row,operation.Get("mode").AsInt32()==0?"Hydraulic":"Thermal",operationId);
            foreach(string action in new[]{"↑","↓","×"})Button(row,action,()=>EditErosion(owner,id,next=>{if(action=="×")next.RemoveAt(slot);else Move(next,slot,action=="↑"?-1:1);}));if(!Get(State(owner,"_expanded_landforms"),operationId,false).AsBool())continue;
            var specs=new List<(string Title,string Key,double Low,double High,double Step)>{("Iterations","iterations",1,1000,1),("Strength","strength",0,1,.01)};
            if(operation.Get("mode").AsInt32()==0)specs.AddRange(new[]{("Rainfall","rainfall",0.0,1.0,.005),("Sediment capacity","sediment_capacity",0.0,20.0,.1),("Deposition rate","deposition_rate",0.0,1.0,.01),("Evaporation","evaporation",0.0,1.0,.01),("Flow rate","flow_rate",0.0,1.0,.01),("Minimum slope","minimum_slope",0.0,1.0,.001),("Rain seed","seed",-100000.0,100000.0,1.0)});else specs.AddRange(new[]{("Talus angle","talus_angle",0.0,85.0,1.0),("Material mobility","mobility",0.0,1.0,.01)});
            foreach(var spec in specs)Number(parent,spec.Title,operation.Get(spec.Key).AsDouble(),spec.Low,spec.High,spec.Step,value=>EditErosion(owner,id,next=>next[slot].As<Resource>().Set(spec.Key,spec.Key is "iterations" or "seed"?Variant.From((long)value):Variant.From(value))));
            var mask=operation.Get("mask").AsGodotDictionary();Toggle(parent,"Limit to circular region",mask.Count>0,value=>EditErosion(owner,id,next=>next[slot].As<Resource>().Set("mask",value?new Settings {["center"]=Vector2.Zero,["radius"]=terrain.Get("dimensions").AsVector2().Length()*.2,["falloff"] = .3}:new Settings())));
            if(mask.Count==0)continue;for(int axis=0;axis<2;axis++){int component=axis;Number(parent,"Region "+new[]{"X","Z"}[axis],Get(mask,"center",Vector2.Zero).AsVector2()[axis],-100000,100000,.1,value=>EditErosion(owner,id,next=>{var target=next[slot].As<Resource>().Get("mask").AsGodotDictionary();var center=Get(target,"center",Vector2.Zero).AsVector2();center[component]=(float)value;target["center"]=center;}));}foreach(var spec in new[]{("Region radius","radius",5.0,.01,100000.0,.1),("Region falloff","falloff",.3,.01,1.0,.01)})Number(parent,spec.Item1,Get(mask,spec.Item2,spec.Item3).AsDouble(),spec.Item4,spec.Item5,spec.Item6,value=>EditErosion(owner,id,next=>next[slot].As<Resource>().Get("mask").AsGodotDictionary()[spec.Item2]=value));
        }
    }
    public void generation_properties(Control owner,Resource item,Resource terrain)
    {
        string id=item.Get("id").AsString();var parent=Field<VBoxContainer>(owner,"properties");var generation=terrain.Get("generation").As<Resource>();var profile=MenuChoice(parent,new[]{"Original noise"}.Concat(Profiles).ToArray(),generation==null?0:generation.Get("profile").AsInt32()+1,index=>{if(index==0){regenerate_terrain(owner,id,new Settings {["generation"]=default},false,false);return;}regenerate_terrain(owner,id,new Settings {["generation"]=_generation.preset(index-1),["amplitude"]=new[]{0.0,8,25,18,15,7,20,15,8,8}[index-1],["frequency"]=.04},false,false);});profile.FitToLongestItem=false;
        Toggle(parent,"Advanced noise & landforms",owner.Get("_advanced_generation").AsBool(),value=>{owner.Set("_advanced_generation",value);refresh_properties(owner);});if(!owner.Get("_advanced_generation").AsBool())return;generation??=_generation.preset(9);
        MenuChoice(parent,new[]{"Simplex fractal","Perlin fractal","Ridged fractal","Cellular","Domain warped"},generation.Get("noise_type").AsInt32(),index=>EditGeneration(owner,id,next=>next.Set("noise_type",index)));
        foreach(var spec in new[]{("Octaves","octaves",1.0,10.0,1.0),("Lacunarity","lacunarity",1.0,5.0,.1),("Gain","gain",.01,1.0,.01),("Medium scale","medium_weight",0.0,2.0,.01),("Fine scale","fine_weight",0.0,1.0,.01),("Warp distance","warp_strength",0.0,1000.0,.1),("Peak sharpness","sharpness",.1,8.0,.1),("Direction","direction",-360.0,360.0,1.0),("Island radius","island_radius",.1,1.5,.01),("Coast transition","transition",.01,1.0,.01)})Number(parent,spec.Item1,generation.Get(spec.Item2).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>EditGeneration(owner,id,next=>next.Set(spec.Item2,spec.Item2=="octaves"?Variant.From((long)value):Variant.From(value))));
        Menu(parent,"＋ Geological landform ▾",Landforms,index=>{string layerId=Guid.NewGuid().ToString("N");State(owner,"_expanded_landforms")[layerId]=true;EditGeneration(owner,id,next=>next.Get("layers").AsGodotArray().Add(new Settings {["id"]=layerId,["type"]=Landforms[index],["enabled"]=true,["center"]=Vector2.Zero,["width"]=5.0,["length"]=12.0,["height"]=5.0,["direction"]=0.0,["sharpness"]=2.0,["blend"]="add"}));});
        var layers=generation.Get("layers").AsGodotArray();for(int index=0;index<layers.Count;index++)
        {
            int slot=index;var layer=layers[index].AsGodotDictionary();string layerId=Get(layer,"id",index).AsString();Settings Layer(Resource next)=>next.Get("layers").AsGodotArray()[slot].AsGodotDictionary();var row=new HBoxContainer();parent.AddChild(row);var enabled=new CheckBox {ButtonPressed=Get(layer,"enabled",true).AsBool()};row.AddChild(enabled);enabled.Toggled+=value=>EditGeneration(owner,id,next=>Layer(next)["enabled"]=value);ExpandButton(owner,row,Get(layer,"type","Landform").AsString(),layerId);
            foreach(string action in new[]{"↑","↓","×"})Button(row,action,()=>EditGeneration(owner,id,next=>{var entries=next.Get("layers").AsGodotArray();if(action=="×")entries.RemoveAt(slot);else Move(entries,slot,action=="↑"?-1:1);}));if(!Get(State(owner,"_expanded_landforms"),layerId,false).AsBool())continue;
            for(int axis=0;axis<2;axis++){int component=axis;Number(parent,"Center "+new[]{"X","Z"}[axis],Get(layer,"center",Vector2.Zero).AsVector2()[axis],-100000,100000,.1,value=>EditGeneration(owner,id,next=>{var target=Layer(next);var center=Get(target,"center",Vector2.Zero).AsVector2();center[component]=(float)value;target["center"]=center;}));}
            foreach(var spec in new[]{("Width","width",.01,100000.0,.1),("Length","length",.01,100000.0,.1),("Height","height",-10000.0,10000.0,.1),("Direction","direction",-360.0,360.0,1.0),("Sharpness","sharpness",.1,8.0,.1)})Number(parent,spec.Item1,Get(layer,spec.Item2,1.0).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>EditGeneration(owner,id,next=>Layer(next)[spec.Item2]=value));
            string[] blends={"add","maximum","minimum","replace"};MenuChoice(parent,blends,Math.Max(0,Array.IndexOf(blends,Get(layer,"blend","add").AsString())),choice=>EditGeneration(owner,id,next=>Layer(next)["blend"]=blends[choice]));var mask=Get(layer,"mask",new Settings()).AsGodotDictionary();Toggle(parent,"Limit to circular region",mask.Count>0,value=>EditGeneration(owner,id,next=>{var target=Layer(next);target["mask"]=value?new Settings {["center"]=Get(target,"center",Vector2.Zero),["radius"]=Get(target,"width",5.0).AsDouble()*2,["falloff"]=.3}:new Settings();}));if(mask.Count>0)foreach(var spec in new[]{("Region radius","radius",10.0,.01,100000.0,.1),("Region falloff","falloff",.3,.01,1.0,.01)})Number(parent,spec.Item1,Get(mask,spec.Item2,spec.Item3).AsDouble(),spec.Item4,spec.Item5,spec.Item6,value=>EditGeneration(owner,id,next=>Layer(next)["mask"].AsGodotDictionary()[spec.Item2]=value));
        }
    }
    private static OptionButton MenuChoice(Node parent,string[] labels,int selected,Action<int> edit)
    {var choice=new OptionButton();parent.AddChild(choice);foreach(string label in labels)choice.AddItem(label);choice.Select(selected);choice.ItemSelected+=index=>edit((int)index);return choice;}
}
