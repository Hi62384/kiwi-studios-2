using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainDataOperations
{
    private readonly TerrainCaveBiomes _caveBiomes=new();
    private readonly TerrainCaveWater _caveWater=new();
    private sealed class BiomeSamples
    {
        internal (long Key,long Revision,long Preview,int N,Vector2 Dimensions) Version;
        internal readonly Dictionary<string,float[]> Weights=new(StringComparer.Ordinal);
    }
    private static readonly ConditionalWeakTable<Resource,BiomeSamples> BiomeCache=new();
    private static void Prepare(Resource source,Settings cancellation)
    {if(Get(cancellation,"enabled",false).AsBool())source.Call("prepare",cancellation["callback"]);else source.Call("prepare");}
    public bool biomes_valid(Resource source)
    {source.Call("prepare");return source.Get("biomes").As<Resource>()==null||(source.Call("water_valid").AsBool()&&source.Get("biome_key").AsInt64()==climate_key(source)&&source.Get("biome_data").AsGodotDictionary().Count>0);}
    public bool prepare_biomes(Resource source,Settings cancellation)
    {
        var biomes=source.Get("biomes").As<Resource>();if(biomes==null){source.Set("biome_data",new Settings());source.Set("biome_key",0);BiomeCache.Remove(source);return true;}if(biomes_valid(source))return true;var result=_biomes.generate(biomes,source,source.Get("seed").AsInt64(),cancellation);if(Get(result,"cancelled",false).AsBool())return false;string error=Get(result,"error", "").AsString();if(error.Length>0){source.Set("water_status",error);return false;}source.Set("biome_data",result);source.Set("biome_key",climate_key(source));BiomeCache.Remove(source);return true;
    }
    public bool cave_biomes_valid(Resource source)
    {var biomes=source.Get("biomes").As<Resource>();return biomes==null||source.Get("caves").AsGodotArray().Count==0||!_biomes.has_cave_rules(biomes)||(biomes_valid(source)&&source.Get("cave_biome_key").AsInt64()==cave_climate_key(source));}
    public bool prepare_cave_biomes(Resource source,Settings cancellation)
    {
        var biomes=source.Get("biomes").As<Resource>();if(biomes==null||source.Get("caves").AsGodotArray().Count==0||!_biomes.has_cave_rules(biomes)){source.Set("cave_biome_data",new Settings());source.Set("cave_biome_key",0);return true;}if(cave_biomes_valid(source))return true;var data=_caveBiomes.generate(source,cancellation);if(Get(data,"cancelled",false).AsBool())return false;string error=Get(data,"error", "").AsString();if(error.Length>0){source.Set("volume_status",error);return false;}source.Set("cave_biome_data",data);source.Set("cave_biome_key",cave_climate_key(source));return true;
    }
    public Settings cave_biome_at(Resource source,Vector3 point)=>_caveBiomes.query(source,point);
    public Settings biome_at(Resource source,Vector2 point)
    {
        var data=source.Get("biome_data").AsGodotDictionary();if(source.Get("biomes").As<Resource>()==null||data.Count==0)return new Settings();var dimensions=source.Get("dimensions").AsVector2();var uv=point/dimensions+Vector2.One*.5f;if(uv.X<0||uv.Y<0||uv.X>1||uv.Y>1)return new Settings();int n=source.Get("resolution").AsInt32();var version=(source.Get("biome_key").AsInt64(),source.Get("revision").AsInt64(),Get(data,"preview_revision",0).AsInt64(),n,dimensions);var samples=BiomeCache.GetValue(source,_=>new BiomeSamples());if(samples.Version!=version||samples.Weights.Count==0){samples.Version=version;samples.Weights.Clear();foreach(var pair in Get(data,"weights",new Settings()).AsGodotDictionary())samples.Weights[pair.Key.AsString()]=pair.Value.AsFloat32Array();}var p=uv*(n-1);var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;var result=new Settings();foreach(var pair in samples.Weights){double weight=0;for(int z=0;z<2;z++)for(int x=0;x<2;x++)weight+=pair.Value[Math.Min(cell.X+x,n-1)+Math.Min(cell.Y+z,n-1)*n]*(double)(x==1?f.X:1-f.X)*(z==1?f.Y:1-f.Y);result[pair.Key]=weight;}return result;
    }
    private static double VoidDistance(Vector3 point,List<TerrainCaveField> sources)
    {double distance=double.PositiveInfinity;foreach(var cave in sources)distance=Math.Min(distance,cave.Distance(point));return distance;}
    public double water_void_distance(Vector3 point,Godot.Collections.Array sources)
    {var fields=new List<TerrainCaveField>();foreach(var value in sources)fields.Add(new TerrainCaveField(value.As<Resource>()));return VoidDistance(point,fields);}
    public Settings water_cave_ground(Resource source,float[] ground,Settings cancellation)
    {
        var output=(float[])ground.Clone();double lower=double.PositiveInfinity;var caves=new List<TerrainCaveField>();foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;_caves.prepare(cave);var field=new TerrainCaveField(cave);caves.Add(field);lower=Math.Min(lower,field.Bounds().Position.Y);}if(caves.Count==0)return new Settings {["ground"]=output};double step=Math.Max(.05,Math.Min(.25,source.Get("voxel_height").AsDouble()*.5));long visited=0,budget=Math.Max(1000,source.Get("voxel_cell_budget").AsInt64());int n=source.Get("resolution").AsInt32();var dimensions=source.Get("dimensions").AsVector2();for(int z=0;z<n;z++)
        {
            if(Cancelled(cancellation))return new Settings();for(int x=0;x<n;x++)
            {
                int index=x+z*n;var point=new Vector3((float)((x/(double)(n-1)-.5)*dimensions.X),ground[index],(float)((z/(double)(n-1)-.5)*dimensions.Y));if(VoidDistance(point,caves)>=0)continue;double above=point.Y;while(point.Y>lower-step){visited++;if(visited>budget){source.Set("water_status","Cave water sampling budget exceeded. Reduce extent or increase the voxel budget.");return new Settings();}if(visited%128==0&&Cancelled(cancellation))return new Settings();point.Y-=(float)step;if(VoidDistance(point,caves)>=0){double below=point.Y;for(int iteration=0;iteration<12;iteration++){point.Y=(float)((above+below)*.5);if(VoidDistance(point,caves)<0)above=point.Y;else below=point.Y;}output[index]=(float)((above+below)*.5);break;}above=point.Y;}
            }
        }
        return new Settings {["ground"]=output};
    }
    public bool prepare_water(Resource source,Settings cancellation)
    {
        Prepare(source,cancellation);WaterCache.Remove(source);source.Set("water_status", "");var hydrology=source.Get("hydrology").As<Resource>();if(hydrology==null){source.Set("water_delta",Array.Empty<float>());source.Set("water_data",new Settings());source.Set("water_key",0);SampleCache.Remove(source);return true;}long key=hydrology_key(source);int n=source.Get("resolution").AsInt32();if(source.Get("water_key").AsInt64()==key&&source.Get("water_delta").AsFloat32Array().Length==n*n)return true;var baseline=source.Get("_base").AsFloat32Array();var edits=source.Get("edits").AsFloat32Array();var ground=new float[n*n];for(int index=0;index<ground.Length;index++)ground[index]=baseline[index]+edits[index];var input=ground;bool caves=hydrology.Get("enabled").AsBool()&&source.Get("caves").AsGodotArray().Count>0;if(caves){var exposed=water_cave_ground(source,ground,cancellation);if(!exposed.TryGetValue("ground",out var buffer))return false;input=buffer.AsFloat32Array();}var result=_hydrology.generate(hydrology,input,n,source.Get("dimensions").AsVector2(),source.Get("seed").AsInt64(),cancellation);if(Get(result,"cancelled",false).AsBool())return false;string error=Get(result,"error", "").AsString();if(error.Length>0){source.Set("water_status",error);return false;}var previousDelta=source.Get("water_delta");var previousData=source.Get("water_data");var delta=result["delta"].AsFloat32Array();for(int index=0;index<ground.Length;index++)delta[index]+=input[index]-ground[index];source.Set("water_delta",delta);result.Remove("delta");source.Set("water_data",result);SampleCache.Remove(source);if(caves){var caveWater=_caveWater.generate(source,cancellation);string caveError=Get(caveWater,"error", "").AsString();if(Get(caveWater,"cancelled",false).AsBool()||caveError.Length>0){source.Set("water_status",caveError);source.Set("water_delta",previousDelta);source.Set("water_data",previousData);SampleCache.Remove(source);return false;}if(caveWater.TryGetValue("mesh",out var mesh))result["mesh"]=mesh;caveWater.Remove("mesh");result["cave_volume"]=caveWater;}source.Set("water_key",key);mark_all_dirty(source);return true;
    }
}
