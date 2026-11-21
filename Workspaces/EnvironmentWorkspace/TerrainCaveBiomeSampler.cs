using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

internal sealed class TerrainCaveBiomeSampler
{
    private readonly Vector3 _origin,_spacing;
    private readonly Vector3I _size;
    private readonly Dictionary<string,float[]> _weights=new(StringComparer.Ordinal);
    internal TerrainCaveBiomeSampler(Resource terrain)
    {var data=terrain.Get("cave_biome_data").AsGodotDictionary();if(data.Count==0)return;_origin=data["origin"].AsVector3();_spacing=data["spacing"].AsVector3();_size=data["size"].AsVector3I();foreach(var pair in data["weights"].AsGodotDictionary())_weights[pair.Key.AsString()]=pair.Value.AsFloat32Array();}
    internal Dictionary<string,double> Sample(Vector3 point)
    {
        var result=new Dictionary<string,double>(StringComparer.Ordinal);if(_weights.Count==0)return result;var p=(point-_origin)/_spacing;if(p.X<0||p.Y<0||p.Z<0||p.X>_size.X-1||p.Y>_size.Y-1||p.Z>_size.Z-1)return result;
        var floor=(Vector3I)p.Floor();var cell=new Vector3I(Math.Min(floor.X,_size.X-2),Math.Min(floor.Y,_size.Y-2),Math.Min(floor.Z,_size.Z-2));var f=p-(Vector3)cell;double total=0;
        foreach(var pair in _weights){double value=0;for(int z=0;z<2;z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++)value+=pair.Value[cell.X+x+(cell.Y+y)*_size.X+(cell.Z+z)*_size.X*_size.Y]*(double)(x==1?f.X:1-f.X)*(y==1?f.Y:1-f.Y)*(z==1?f.Z:1-f.Z);result[pair.Key]=value;total+=value;}
        if(total<=.000001)return new Dictionary<string,double>();foreach(string id in result.Keys.ToArray())result[id]/=total;return result;
    }
}
