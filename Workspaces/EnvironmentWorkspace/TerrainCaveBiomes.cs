using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainCaveBiomes : RefCounted
{
    private readonly TerrainBiomeOperations _biomes=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static double Void(Vector3 point,IReadOnlyList<TerrainCaveField> sources){double distance=double.PositiveInfinity;foreach(var source in sources)distance=Math.Min(distance,source.Distance(point));return distance;}
    private static bool Cancelled(Settings state)=>Get(state,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",state).AsBool();
    public Settings generate(Resource terrain,Settings cancellation)
    {
        var biomes=terrain.Get("biomes").As<Resource>();if(biomes==null)return new Settings();var noises=_biomes.noise_fields(biomes,terrain.Get("seed").AsInt64(),"cave");if(noises.Count==0)return new Settings();
        var sources=new List<TerrainCaveField>();var bounds=new Aabb();bool first=true;
        foreach(var value in terrain.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;cave.Call("prepare");var source=new TerrainCaveField(cave);sources.Add(source);bounds=first?source.Bounds():bounds.Merge(source.Bounds());first=false;}if(first)return new Settings();
        int n=terrain.Get("resolution").AsInt32();var dimensions=terrain.Get("dimensions").AsVector2();double step=Math.Max(.1,terrain.Get("voxel_height").AsDouble());
        var begin=((new Vector2(bounds.Position.X,bounds.Position.Z)/dimensions+Vector2.One*.5f)*(n-1)).Floor();var finish=((new Vector2(bounds.End.X,bounds.End.Z)/dimensions+Vector2.One*.5f)*(n-1)).Ceil();var start=new Vector2I(Math.Max(0,(int)begin.X),Math.Max(0,(int)begin.Y));var end=new Vector2I(Math.Min(n-1,(int)finish.X),Math.Min(n-1,(int)finish.Y));
        var origin=new Vector3((float)((start.X/(double)(n-1)-.5)*dimensions.X),(float)(Math.Floor(bounds.Position.Y/step)*step),(float)((start.Y/(double)(n-1)-.5)*dimensions.Y));var spacing=new Vector3(dimensions.X/(n-1),(float)step,dimensions.Y/(n-1));var size=new Vector3I(end.X-start.X+1,(int)Math.Ceiling((bounds.End.Y-origin.Y)/step)+1,end.Y-start.Y+1);
        if(size.X<2||size.Y<2||size.Z<2)return new Settings();int count=checked(size.X*size.Y*size.Z);if(count>terrain.Get("voxel_cell_budget").AsInt64())return new Settings {["error"]="Cave biome field budget exceeded. Reduce cave extent or increase voxel size/budget."};
        var fields=new Dictionary<string,float[]>();foreach(var id in noises.Keys)fields[id.AsString()]=new float[count];var presence=new byte[count];bool directional=false;
        foreach(var entry in biomes.Get("definitions").AsGodotArray()){var definition=entry.AsGodotDictionary();if(noises.ContainsKey(definition["id"].AsString())&&Get(definition,"surface_type","any").AsString()!="any")directional=true;}
        using var ground=new TerrainVolumeMesher();ground.configure(terrain,new GArray(),new GArray());var biomeData=terrain.Get("biome_data").AsGodotDictionary();var humidity=Get(biomeData,"humidity",Array.Empty<float>()).AsFloat32Array();var temperature=Get(biomeData,"temperature",Array.Empty<float>()).AsFloat32Array();double baseHumidity=biomes.Get("base_humidity").AsDouble(),seaTemperature=biomes.Get("sea_temperature").AsDouble();var waterData=terrain.Get("water_data").AsGodotDictionary();var sampler=new TerrainBiomeSampler(biomes,noises);bool waterVolume=waterData.ContainsKey("cave_volume");var water=new TerrainCaveWater.Sampler(terrain,sources);Variant geology=terrain.Get("geology");
        for(int z=0;z<size.Z;z++)for(int x=0;x<size.X;x++)
        {
            int sourceIndex=start.X+x+(start.Y+z)*n;double elevation=ground.grid_height(start.X+x,start.Y+z),moist=humidity.Length>0?humidity[sourceIndex]:baseHumidity,heat=temperature.Length>0?temperature[sourceIndex]:seaTemperature;
            for(int y=0;y<size.Y;y++)
            {
                int index=x+y*size.X+z*size.X*size.Y;if(index%128==0&&Cancelled(cancellation))return new Settings {["cancelled"]=true};var point=origin+new Vector3(x,y,z)*spacing;
                if(point.Y>elevation+step*.1||Void(point,sources)>Math.Max(Math.Max(spacing.X,spacing.Z),spacing.Y)*.75)continue;
                presence[index]=1;double depth=Math.Max(0,elevation-point.Y);var wet=water.Query(point);var normal=Vector3.Up;
                if(directional||waterVolume){float h=(float)Math.Min(.2,step*.3);var a=new Vector3(h,0,0);var b=new Vector3(0,h,0);var c=new Vector3(0,0,h);normal=-new Vector3((float)(Void(point+a,sources)-Void(point-a,sources)),(float)(Void(point+b,sources)-Void(point-b,sources)),(float)(Void(point+c,sources)-Void(point-c,sources))).Normalized();}
                if(wet.Count==0&&waterVolume)wet=water.Query(point+normal*(float)step*.4f);
                double submersion=wet.Count>0?wet["surface"].AsVector3().Y-point.Y:-10000,moisture=Math.Max(moist,wet.Count>0?.92:.55),climate=seaTemperature*.75+heat*.25+depth*.025;
                string surfaceType=normal.Y>.5?"floor":normal.Y<-.5?"ceiling":"wall";
                var context=new Settings {["domain"]="cave",["geology"]=geology,["cave_depth"]=depth,["submersion"]=submersion,["surface_type"]=surfaceType,["noise_position"]=point};
                var values=sampler.Sample(new Vector2(point.X,point.Z),point.Y,Mathf.RadToDeg(Math.Acos(Math.Clamp(normal.Y,-1,1))),climate,moisture,0.0,0.0,sourceIndex,n,context);
                foreach(var value in values)fields[value.Key][index]=(float)value.Value;
            }
        }
        var result=new Settings();foreach(var field in fields)result[field.Key]=field.Value;return new Settings {["origin"]=origin,["spacing"]=spacing,["size"]=size,["weights"]=result,["presence"]=presence,["voxels"]=count};
    }
    public Settings query(Resource terrain,Vector3 point)
    {
        var data=terrain.Get("cave_biome_data").AsGodotDictionary();if(data.Count==0)return new Settings();var size=data["size"].AsVector3I();var p=(point-data["origin"].AsVector3())/data["spacing"].AsVector3();
        if(p.X<0||p.Y<0||p.Z<0||p.X>size.X-1||p.Y>size.Y-1||p.Z>size.Z-1)return new Settings();var floor=(Vector3I)p.Floor();var cell=new Vector3I(Math.Min(floor.X,size.X-2),Math.Min(floor.Y,size.Y-2),Math.Min(floor.Z,size.Z-2));var f=p-(Vector3)cell;var result=new Settings();double total=0;
        foreach(var field in data["weights"].AsGodotDictionary())
        {
            var values=field.Value.AsFloat32Array();double value=0;for(int z=0;z<2;z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++)value+=values[cell.X+x+(cell.Y+y)*size.X+(cell.Z+z)*size.X*size.Y]*(double)(x==1?f.X:1-f.X)*(y==1?f.Y:1-f.Y)*(z==1?f.Z:1-f.Z);result[field.Key]=value;total+=value;
        }
        if(total<=.000001)return new Settings();foreach(var key in result.Keys.ToArray())result[key]=result[key].AsDouble()/total;return result;
    }
    public double void_distance(Vector3 point,GArray sources)=>Void(point,sources.Select(value=>new TerrainCaveField(value.As<Resource>())).ToArray());
}
