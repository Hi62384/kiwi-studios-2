using Godot;
using System;
using System.Runtime.CompilerServices;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainDataOperations
{
    private sealed class WaterSamples
    {
        internal long Key=long.MinValue;
        internal float[] Depth=Array.Empty<float>(),Levels=Array.Empty<float>();
        internal Vector2[] Flow=Array.Empty<Vector2>();
    }
    private static readonly ConditionalWeakTable<Resource,WaterSamples> WaterCache=new();
    public Settings water_at(Resource source,Vector3 point)
    {
        var hydrology=source.Get("hydrology").As<Resource>();var water=source.Get("water_data").AsGodotDictionary();if(hydrology==null||!hydrology.Get("enabled").AsBool()||water.Count==0||!water.ContainsKey("levels"))return new Settings();var dimensions=source.Get("dimensions").AsVector2();var horizontal=new Vector2(point.X,point.Z);var uv=horizontal/dimensions+Vector2.One*.5f;if(uv.X<0||uv.Y<0||uv.X>1||uv.Y>1)return new Settings();int n=source.Get("resolution").AsInt32();long key=source.Get("water_key").AsInt64();var samples=WaterCache.GetValue(source,_=>new WaterSamples());if(samples.Key!=key||samples.Depth.Length!=n*n){samples.Key=key;samples.Depth=water["depth"].AsFloat32Array();samples.Levels=water["levels"].AsFloat32Array();samples.Flow=water["flow"].AsVector2Array();}var p=uv*(n-1);var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;double level=0,sum=0;var flow=Vector2.Zero;for(int z=0;z<2;z++)for(int x=0;x<2;x++){int index=Math.Min(cell.X+x,n-1)+Math.Min(cell.Y+z,n-1)*n;double weight=(x==1?f.X:1.0-f.X)*(z==1?f.Y:1.0-f.Y);if(samples.Depth[index]<=0)continue;level+=samples.Levels[index]*weight;flow+=samples.Flow[index]*(float)weight;sum+=weight;}if(sum<=.000001)return _caveWater.query(source,point);level/=sum;flow/=(float)sum;double ground=source.Call("sample",horizontal).AsGodotDictionary()["height"].AsDouble();if(point.Y<ground||ground>=level)return _caveWater.query(source,point);return new Settings {["surface"]=new Vector3(point.X,(float)level,point.Z),["depth"]=level-ground,["flow"]=new Vector3(flow.X,0,flow.Y),["inside"]=point.Y<=level&&point.Y>=ground,["bottom"]=ground};
    }
}
