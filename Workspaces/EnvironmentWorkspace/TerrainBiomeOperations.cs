using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainBiomeOperations : RefCounted
{
    private readonly EnvironmentDataHash _hash=new();
    private readonly TerrainGenerationOperations _generation=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static GArray Definitions(Resource owner)=>owner.Get("definitions").AsGodotArray();
    private static GDScript Schema()=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biomes.gd");
    private static bool Cancelled(Settings state)=>Get(state,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",state).AsBool();
    public long signature(Resource owner)
    {using var values=new GArray {4};foreach(string field in new[]{"definitions","fallback_id","cave_fallback_id","sea_temperature","latitude_range","altitude_lapse","base_humidity","climate_region_size","paint_masks"})values.Add(owner.Get(field));return _hash.value(values);}
    public long climate_signature(Resource owner)
    {
        using var rules=new GArray();foreach(var entry in Definitions(owner)){var rule=entry.AsGodotDictionary().Duplicate();rule.Remove("materials");rule.Remove("name");rules.Add(rule);}
        using var values=new GArray {4,rules};foreach(string field in new[]{"fallback_id","cave_fallback_id","sea_temperature","latitude_range","altitude_lapse","base_humidity","climate_region_size","paint_masks"})values.Add(owner.Get(field));return _hash.value(values);
    }
    public long landform_signature(Resource owner)
    {foreach(var entry in Definitions(owner)){var value=entry.AsGodotDictionary();if(Get(value,"enabled",true).AsBool()&&Get(value,"landforms",new GArray()).AsGodotArray().Count>0)return climate_signature(owner);}return 0;}
    public bool has_cave_rules(Resource owner)=>Definitions(owner).Any(entry=>Get(entry.AsGodotDictionary(),"enabled",true).AsBool()&&Get(entry.AsGodotDictionary(),"domain","surface").AsString()=="cave");
    public Settings noise_fields(Resource owner,long seed,string domain)
    {
        var result=new Settings();foreach(var entry in Definitions(owner))
        {
            var value=entry.AsGodotDictionary();if(!Get(value,"enabled",true).AsBool()||Get(value,"domain","surface").AsString()!=domain)continue;string id=value["id"].AsString();
            result[id]=new FastNoiseLite {Seed=unchecked((int)(seed+unchecked((uint)GD.Hash(id))%1000000)),Frequency=(float)(1/Math.Max(1,Get(value,"region_size",80.0).AsDouble()))};
        }
        return result;
    }
    public string[] validate(Resource owner)
    {
        var errors=new List<string>();var ids=new HashSet<string>(StringComparer.Ordinal);
        if(new[]{"sea_temperature","base_humidity","altitude_lapse","climate_region_size"}.Any(field=>!double.IsFinite(owner.Get(field).AsDouble()))||!owner.Get("latitude_range").AsVector2().IsFinite())errors.Add("Climate values must be finite.");
        foreach(var entry in Definitions(owner))
        {
            var definition=entry.AsGodotDictionary();string id=Get(definition,"id", "").AsString();if(id.Length==0||!ids.Add(id))errors.Add("Every biome needs a unique stable ID.");
            foreach(string key in new[]{"frequency","region_size","transition","weight"})if(!double.IsFinite(Get(definition,key,1.0).AsDouble()))errors.Add("Biome suitability values must be finite.");
            var generator=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_generator.gd").New().As<Resource>();var layers=generator.Get("layers").AsGodotArray();foreach(var layer in Get(definition,"landforms",new GArray()).AsGodotArray())layers.Add(layer);errors.AddRange(_generation.validate(generator));
            foreach(string key in new[]{"temperature","humidity","altitude","slope","shore_distance","roughness"}){var limits=Get(definition,key,new Vector2(-100000,100000)).AsVector2();if(!limits.IsFinite()||limits.X>limits.Y)errors.Add("Biome ranges must be finite and ordered.");}
        }
        return errors.ToArray();
    }
    public Settings weights_sample(Resource owner,Vector2 point,double elevation,double slope,double temperature,double humidity,double shore,double roughness,int index,int n,Settings noises,Settings features)
    {var result=new Settings();foreach(var pair in new TerrainBiomeSampler(owner,noises).Sample(point,elevation,slope,temperature,humidity,shore,roughness,index,n,features))result[pair.Key]=pair.Value;return result;}
    public double range(double value,Vector2 limits,double transition)=>TerrainBiomeSampler.Range(value,limits,transition);
    public double mask_at(float[] mask,int x,int z,int n)=>TerrainBiomeSampler.MaskAt(mask,x,z,n);
    public Settings starter(int index)
    {
        index=Math.Clamp(index,0,13);string[] ids={"grassland","forest","desert","tropical","jungle","savanna","swamp","snow","alpine","mountains","badlands","volcanic","beach","rocky_coast"};
        Vector2[] temperatures={new(4,30),new(-4,25),new(16,60),new(22,45),new(23,45),new(18,40),new(8,38),new(-80,3),new(-15,12),new(-50,40),new(8,45),new(-80,80),new(0,50),new(-40,40)};
        Vector2[] humidity={new(.2f,.75f),new(.45f,1),new(0,.3f),new(.5f,1),new(.7f,1),new(.12f,.5f),new(.7f,1),new(0,1),new(0,1),new(0,1),new(0,.4f),new(0,1),new(0,1),new(0,1)};
        Vector2[] slopes={new(0,35),new(0,45),new(0,50),new(0,55),new(0,45),new(0,30),new(0,8),new(0,60),new(15,70),new(35,90),new(12,75),new(0,90),new(0,15),new(25,90)};
        var names=Schema().GetScriptConstantMap()["NAMES"].AsGodotArray();
        var result=new Settings {["id"]=ids[index],["name"]=names[index],["enabled"]=true,["temperature"]=temperatures[index],["humidity"]=humidity[index],["altitude"]=new Vector2(-10000,10000),["slope"]=slopes[index],["shore_distance"]=index is 6 or 12 or 13?new Vector2(-10000,8):new Vector2(-100000,100000),["roughness"]=new Vector2(0,10000),["frequency"]=index is 10 or 11?.2:1.0,["region_size"]=80.0,["transition"]=.2,["weight"]=1.0,["materials"]=new GArray()};
        if(index==11)result["geology"]=new GArray {4,5};if(index==10)result["geology"]=new GArray {3};return result;
    }
    public Settings cave_starter(int index)
    {
        index=Math.Clamp(index,0,5);var result=starter(0);result["id"]="cave_"+new[]{"dry","damp","flooded","cold","limestone","volcanic"}[index];result["name"]=Schema().GetScriptConstantMap()["CAVE_NAMES"].AsGodotArray()[index];result["domain"]="cave";result["temperature"]=new Vector2(-100,100);result["humidity"]=new Vector2(0,1);result["slope"]=new Vector2(0,180);result["cave_depth"]=new Vector2(0,10000);result["surface_type"]="any";result["submersion"]=new Vector2(-10000,10000);result["region_size"]=40.0;
        var material=new StandardMaterial3D {AlbedoColor=new Color(new[]{"625b52","30433c","354652","9fbbc7","b2a788","29201d"}[index]),Roughness=.9f};result["materials"]=new GArray {material};
        switch(index){case 0:result["humidity"]=new Vector2(0,.65f);result["submersion"]=new Vector2(-10000,0);break;case 1:result["humidity"]=new Vector2(.6f,1);break;case 2:result["submersion"]=new Vector2(0,10000);break;case 3:result["temperature"]=new Vector2(-100,4);break;case 4:result["geology"]=new GArray {2};break;case 5:result["geology"]=new GArray {4,5};break;}return result;
    }
}
