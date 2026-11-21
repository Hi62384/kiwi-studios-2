using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

internal sealed class EnvironmentTerrainSampler : IDisposable
{
    private readonly TerrainVolumeMesher _heights=new();
    internal readonly int N;
    internal readonly Vector2 Dimensions;
    internal readonly float[] Temperature,Humidity,Shore,Depths;
    private readonly float[] _levels;
    private readonly Dictionary<string,float[]> _biomes=new(StringComparer.Ordinal);
    private readonly TerrainCaveBiomeSampler _caveBiomes;
    private readonly TerrainCaveWater.Sampler _caveWater;
    private readonly bool _waterEnabled;
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    internal EnvironmentTerrainSampler(Resource terrain)
    {
        N=terrain.Get("resolution").AsInt32();Dimensions=terrain.Get("dimensions").AsVector2();_heights.configure(terrain,new GArray(),new GArray());var biome=terrain.Get("biome_data").AsGodotDictionary();var water=terrain.Get("water_data").AsGodotDictionary();
        Temperature=Get(biome,"temperature",Array.Empty<float>()).AsFloat32Array();Humidity=Get(biome,"humidity",Array.Empty<float>()).AsFloat32Array();Shore=Get(water,"shore_distance",Array.Empty<float>()).AsFloat32Array();Depths=Get(water,"depth",Array.Empty<float>()).AsFloat32Array();_levels=Get(water,"levels",Array.Empty<float>()).AsFloat32Array();
        if(terrain.Get("biomes").As<Resource>()!=null)foreach(var pair in Get(biome,"weights",new Settings()).AsGodotDictionary())_biomes[pair.Key.AsString()]=pair.Value.AsFloat32Array();
        var hydrology=terrain.Get("hydrology").As<Resource>();_waterEnabled=hydrology!=null&&hydrology.Get("enabled").AsBool()&&_levels.Length>0;_caveBiomes=new TerrainCaveBiomeSampler(terrain);_caveWater=new TerrainCaveWater.Sampler(terrain);
    }
    internal bool Inside(Vector2 point){var uv=point/Dimensions+Vector2.One*.5f;return uv.X>=0&&uv.Y>=0&&uv.X<=1&&uv.Y<=1;}
    internal double Height(Vector2 point)=>_heights.height(point);
    internal int Index(Vector2 point)=>Math.Clamp((int)Math.Round((point.X/(double)Dimensions.X+.5)*(N-1),MidpointRounding.AwayFromZero),0,N-1)+Math.Clamp((int)Math.Round((point.Y/(double)Dimensions.Y+.5)*(N-1),MidpointRounding.AwayFromZero),0,N-1)*N;
    internal Vector3 Normal(Vector2 point)
    {
        var p=((point/Dimensions+Vector2.One*.5f)*(N-1)).Floor();int x=(int)p.X,z=(int)p.Y;double dx=(_heights.grid_height(x+1,z)-_heights.grid_height(x-1,z))/(Dimensions.X/(double)(N-1)*2),dz=(_heights.grid_height(x,z+1)-_heights.grid_height(x,z-1))/(Dimensions.Y/(double)(N-1)*2);return new Vector3((float)-dx,1,(float)-dz).Normalized();
    }
    internal Dictionary<string,double> Biome(Vector2 point)
    {
        var result=new Dictionary<string,double>(StringComparer.Ordinal);if(!Inside(point))return result;var p=(point/Dimensions+Vector2.One*.5f)*(N-1);var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;
        foreach(var field in _biomes){double value=0;for(int z=0;z<2;z++)for(int x=0;x<2;x++)value+=field.Value[Math.Min(cell.X+x,N-1)+Math.Min(cell.Y+z,N-1)*N]*(double)(x==1?f.X:1-f.X)*(z==1?f.Y:1-f.Y);result[field.Key]=value;}return result;
    }
    internal Dictionary<string,double> CaveBiome(Vector3 point)=>_caveBiomes.Sample(point);
    internal double WaterDepth(Vector3 point)
    {
        var horizontal=new Vector2(point.X,point.Z);if(!_waterEnabled||!Inside(horizontal))return 0;var p=(horizontal/Dimensions+Vector2.One*.5f)*(N-1);var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;double level=0,sum=0;
        for(int z=0;z<2;z++)for(int x=0;x<2;x++){int index=Math.Min(cell.X+x,N-1)+Math.Min(cell.Y+z,N-1)*N;double weight=(x==1?f.X:1.0-f.X)*(z==1?f.Y:1.0-f.Y);if(Depths[index]<=0)continue;level+=_levels[index]*weight;sum+=weight;}
        double ground=Height(horizontal);if(sum<=.000001||point.Y<ground||ground>=level/sum){var cave=_caveWater.Query(point);return Get(cave,"depth",0.0).AsDouble();}return level/sum-ground;
    }
    public void Dispose()=>_heights.Dispose();
}
