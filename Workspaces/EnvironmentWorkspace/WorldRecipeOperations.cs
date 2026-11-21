using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldRecipeOperations : RefCounted
{
    private static readonly string[] Names={"Modern City","Suburban Town","Rural Countryside","Medieval Village","Mountain Region","Tropical Island","Fantasy World"};
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public bool empty(Resource? source)
    {return source!=null&&new[]{"roads","settlements","forests","prop_rules","exclusions"}.All(key=>source.Get(key).AsGodotArray().Count==0)&&source.Get("plot_overrides").AsGodotDictionary().Count==0&&!source.Get("regions").AsGodotArray().Any(value=>Get(value.AsGodotDictionary(),"locked",false).AsBool());}
    public Settings configure(Resource source,string name,Settings presets,Settings species)
    {
        int recipeIndex=Array.IndexOf(Names,name);if(recipeIndex<0||!empty(source))return new Settings {["error"]="Choose an empty world before generating a preset. Existing authored sources are preserved."};var next=new WorldSourceOperations().copy(source);var dimensions=source.Get("dimensions").AsVector2();double scale=Math.Min(dimensions.X,dimensions.Y);string profile="Town",style="Modern",forest="";int terrainProfile=0,blocks=3,height=2;double amplitude=0,radius=Math.Min(64,scale*.25),level=0;using var rng=new RandomNumberGenerator();rng.Seed=unchecked((ulong)source.Get("seed").AsInt64());double angle=rng.RandfRange(-.2f,.2f);
        switch(name){case "Modern City":profile="City";blocks=4;height=6;radius=Math.Min(80,scale*.3);break;case "Suburban Town":forest="Sparse Woodland";style="Traditional";terrainProfile=1;amplitude=.6;break;case "Rural Countryside":profile="Village";forest="Sparse Woodland";style="Cottage";radius=Math.Max(8,scale*.1);terrainProfile=1;amplitude=1.5;break;case "Medieval Village":profile="Village";forest="Temperate Forest";style="Medieval";radius=Math.Max(8,scale*.14);terrainProfile=1;amplitude=1;break;case "Mountain Region":profile="Village";forest="Alpine Forest";style="Cabin";radius=Math.Max(8,scale*.06);terrainProfile=2;amplitude=24;break;case "Tropical Island":profile="Village";forest="Tropical Jungle";style="Cabin";radius=Math.Max(8,scale*.1);terrainProfile=3;amplitude=14;level=4;break;case "Fantasy World":forest="Temperate Forest";style="Fantasy";terrainProfile=7;amplitude=10;radius=Math.Max(8,scale*.12);blocks=2;height=3;level=3;break;}
        var centers=name=="Rural Countryside"?new[]{new Vector3((float)(-scale*.22),0,(float)(Math.Sin(angle)*scale*.15)),new Vector3((float)(scale*.22),0,(float)(-Math.Sin(angle)*scale*.15))}:new[]{Vector3.Zero};var generation=new TerrainGenerationOperations().preset(terrainProfile);var cities=new WorldSettlementOperations();var styles=new BuildingStyleOperations();var districts=new WorldDistrictOperations();
        foreach(var center in centers)
        {
            next=cities.create(next,center,profile,presets);var settlements=next.Get("settlements").AsGodotArray();int index=settlements.Count-1;var settlement=settlements[index].AsGodotDictionary();string id="recipe:"+recipeIndex+":settlement:"+index;settlement["id"]=id;settlement["seed"]=unchecked((uint)GD.Hash(new GArray {source.Get("seed"),index}));settlement["radius"]=radius;settlement["blocks"]=blocks;settlement["height_max"]=height;var styled=styles.apply(settlement["template"].As<Resource>(),style,presets);settlement["template"]=styled!=null?Variant.From(styled):default;
            if(terrainProfile is 2 or 3 or 7){double span=radius*1.2;var polygon=new[]{new Vector2((float)(center.X-span),(float)(center.Z-span)),new Vector2((float)(center.X+span),(float)(center.Z-span)),new Vector2((float)(center.X+span),(float)(center.Z+span)),new Vector2((float)(center.X-span),(float)(center.Z+span))};generation.Get("layers").AsGodotArray().Add(new Settings {["id"]="recipe:clearing:"+index,["type"]="Foundation",["polygon"]=polygon,["plane"]=new Plane(Vector3.Up,(float)level),["feather"]=Math.Max(4,radius*.5),["enabled"]=true});}
            settlement["road_type"]=name is "Rural Countryside" or "Medieval Village" or "Fantasy World"?"Dirt Road":name=="Mountain Region"?"Forest Track":"Residential Street";
            if(name is "Modern City" or "Suburban Town")
            {
                float central=(float)(radius*.48);var polygon=new[]{new Vector2(-central,-central),new Vector2(central,-central),new Vector2(central,central),new Vector2(-central,central)};var district=districts.create(name=="Modern City"?"Downtown":"Park/Green Space",polygon,presets);district["id"]=id+":central";district["seed"]=source.Get("seed");var list=new GArray {district};settlement["districts"]=list;
                if(name=="Modern City"){var industrial=districts.create("Industrial",new[]{new Vector2((float)-radius,(float)(radius*.5)),new Vector2((float)radius,(float)(radius*.5)),new Vector2((float)radius,(float)radius),new Vector2((float)-radius,(float)radius)},presets);industrial["id"]=id+":industrial";list.Add(industrial);}
            }
        }
        if(forest.Length>0){next=new WorldForestOperations().create(next,Vector3.Zero,forest,species);var value=next.Get("forests").AsGodotArray()[0].AsGodotDictionary();value["id"]="recipe:forest";value["budget"]=750;value["density"]=forest!="Sparse Woodland"?.5:.3;}
        var library=new WorldPropLibraryOperations();foreach(string kind in name is "Modern City" or "Suburban Town"?new[]{"Park bench","Street lamp"}:new[]{"Rock cluster"}){next=library.add(next,kind);var rules=next.Get("prop_rules").AsGodotArray();var value=rules[^1].AsGodotDictionary();value["id"]="recipe:prop:"+(rules.Count-1);value["budget"]=200;}
        Resource? water=null;if(name=="Tropical Island"){water=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_hydrology.gd").New().As<Resource>();water.Set("automatic_rivers",false);water.Set("automatic_lakes",false);water.Set("ocean_enabled",true);water.Set("sea_level",0.0);water.Set("water_color",new Color(.08f,.65f,.72f,.92f));}
        return new Settings {["error"]="",["source"]=next,["terrain_settings"]=new Settings {["generation"]=generation,["dimensions"]=next.Get("dimensions"),["amplitude"]=amplitude,["base_height"]=0.0,["frequency"]=1/Math.Max(24,scale*.25),["seed"]=source.Get("seed"),["hydrology"]=water!=null?Variant.From(water):default}};
    }
}
