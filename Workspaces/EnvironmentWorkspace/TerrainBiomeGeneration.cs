using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainBiomeOperations
{
    private sealed class Grid
    {
        internal readonly int N;
        internal readonly Vector2 Dimensions;
        internal readonly double[] Heights;
        internal readonly Settings Water;
        internal readonly Variant Geology;
        internal Grid(int n,Vector2 dimensions,float[] values,int geology)
        {N=n;Dimensions=dimensions;Heights=values.Select(value=>(double)value).ToArray();Water=new Settings();Geology=geology;}
        internal Grid(Resource source)
        {
            N=source.Get("resolution").AsInt32();Dimensions=source.Get("dimensions").AsVector2();Heights=new double[N*N];Water=source.Get("water_data").AsGodotDictionary();Geology=source.Get("geology");
            if(source.HasMethod("height_snapshot"))
            {
                var snapshot=source.Call("height_snapshot").AsGodotDictionary();var values=snapshot["base"].AsFloat32Array();var edits=snapshot["edits"].AsFloat32Array();var water=snapshot["water"].AsFloat32Array();
                for(int i=0;i<Heights.Length;i++)Heights[i]=(double)values[i]+edits[i]+(water.Length==Heights.Length?water[i]:0);
            }
            else if(source.GetPropertyList().Any(info=>info["name"].AsString()=="values")){var values=source.Get("values").AsFloat32Array();for(int i=0;i<Heights.Length;i++)Heights[i]=values[i];}
            else for(int z=0;z<N;z++)for(int x=0;x<N;x++)Heights[x+z*N]=source.Call("height",x,z).AsDouble();
        }
        internal double Height(int x,int z)=>Heights[Math.Clamp(x,0,N-1)+Math.Clamp(z,0,N-1)*N];
        internal Vector3 Position(int x,int z)=>new((float)((x/(double)(N-1)-.5)*Dimensions.X),(float)Height(x,z),(float)((z/(double)(N-1)-.5)*Dimensions.Y));
        internal Vector3 Normal(int x,int z)=>new Vector3((float)((Height(x-1,z)-Height(x+1,z))/(Dimensions.X/(double)(N-1)*2)),1,(float)((Height(x,z-1)-Height(x,z+1))/(Dimensions.Y/(double)(N-1)*2))).Normalized();
    }
    public double base_height(Resource source,int x,int z)=>new Grid(source).Height(x,z);
    public Vector3 base_position(Resource source,int x,int z)=>new Grid(source).Position(x,z);
    public Vector3 base_normal(Resource source,int x,int z)=>new Grid(source).Normal(x,z);
    public Settings generate(Resource owner,Resource terrain,long seed,Settings cancellation)=>Generate(owner,new Grid(terrain),seed,cancellation);
    private Settings Generate(Resource owner,Grid grid,long seed,Settings cancellation)
    {
        var errors=validate(owner);if(errors.Length>0)return new Settings {["error"]=string.Join("\n",errors)};
        int n=grid.N,count=n*n;var temperatures=new float[count];var humidities=new float[count];var slopes=new float[count];var roughness=new float[count];var weights=new Dictionary<string,float[]>();var noises=noise_fields(owner,seed,"surface");foreach(var id in noises.Keys)weights[id.AsString()]=new float[count];
        using var climate=new FastNoiseLite {Seed=unchecked((int)seed),Frequency=(float)(1/Math.Max(1,owner.Get("climate_region_size").AsDouble()))};
        var moisture=Get(grid.Water,"moisture",Array.Empty<float>()).AsFloat32Array();var shore=Get(grid.Water,"shore_distance",Array.Empty<float>()).AsFloat32Array();var sampler=new TerrainBiomeSampler(owner,noises);var features=new Settings {["geology"]=grid.Geology};
        var latitudeRange=owner.Get("latitude_range").AsVector2();double sea=owner.Get("sea_temperature").AsDouble(),lapse=owner.Get("altitude_lapse").AsDouble(),humidityBase=owner.Get("base_humidity").AsDouble();var spacing=grid.Dimensions/Math.Max(1,n-1);
        for(int z=0;z<n;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int x=0;x<n;x++)
            {
                int index=x+z*n;var position=grid.Position(x,z);var point=new Vector2(position.X,position.Z);double elevation=position.Y,slope=Mathf.RadToDeg(Math.Acos(Math.Clamp(grid.Normal(x,z).Y,-1,1)));
                double local=Math.Abs(grid.Height(x-1,z)+grid.Height(x+1,z)-elevation*2)/((double)spacing.X*spacing.X)+Math.Abs(grid.Height(x,z-1)+grid.Height(x,z+1)-elevation*2)/((double)spacing.Y*spacing.Y);
                double latitude=Mathf.Lerp((double)latitudeRange.X,latitudeRange.Y,z/(double)Math.Max(1,n-1)),temperature=sea-Math.Abs(latitude)*.35-elevation*lapse+climate.GetNoise2Dv(point)*8.0,humidity=Math.Clamp(humidityBase+climate.GetNoise2D((float)(point.X+1731.0),(float)(point.Y-543.0))*.3+(moisture.Length==count?moisture[index]:0)*.35,0,1);
                temperatures[index]=(float)temperature;humidities[index]=(float)humidity;slopes[index]=(float)slope;roughness[index]=(float)local;
                foreach(var value in sampler.Sample(point,elevation,slope,temperature,humidity,shore.Length==count?shore[index]:100000,local,index,n,features))weights[value.Key][index]=(float)value.Value;
            }
        }
        var fields=new Settings();foreach(var value in weights)fields[value.Key]=value.Value;return new Settings {["weights"]=fields,["temperature"]=temperatures,["humidity"]=humidities,["slope"]=slopes,["roughness"]=roughness,["error"]="",["cancelled"]=false};
    }
    public Settings apply_landforms(Resource owner,float[] heights,int n,Vector2 dimensions,long seed,Settings cancellation,int geology)
    {
        if(landform_signature(owner)==0)return new Settings {["heights"]=heights};var grid=new Grid(n,dimensions,heights,geology);var initial=Generate(owner,grid,seed,cancellation);
        if(Get(initial,"cancelled",false).AsBool()||Get(initial,"error", "").AsString().Length>0)return initial;var output=(float[])heights.Clone();var weights=initial["weights"].AsGodotDictionary();
        var rules=new List<(float[] Weights,Settings[] Layers)>();foreach(var entry in Definitions(owner)){var definition=entry.AsGodotDictionary();if(weights.TryGetValue(definition["id"].AsString(),out var field))rules.Add((field.AsFloat32Array(),Get(definition,"landforms",new GArray()).AsGodotArray().Select(value=>value.AsGodotDictionary()).ToArray()));}
        for(int z=0;z<n;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int x=0;x<n;x++)
            {
                int index=x+z*n;var p=grid.Position(x,z);var point=new Vector2(p.X,p.Z);
                foreach(var rule in rules)foreach(var layer in rule.Layers)
                {
                    if(!Get(layer,"enabled",true).AsBool())continue;double contribution=_generation.landform(point,layer),amount=rule.Weights[index]*_generation.mask(point,Get(layer,"mask",new Settings()).AsGodotDictionary());
                    output[index]=(float)(Get(layer,"blend","add").AsString() switch {"replace"=>Mathf.Lerp(output[index],contribution,amount),"maximum"=>Mathf.Lerp(output[index],Math.Max(output[index],contribution),amount),"minimum"=>Mathf.Lerp(output[index],Math.Min(output[index],contribution),amount),_=>output[index]+contribution*amount});
                }
            }
        }
        return new Settings {["heights"]=output,["initial_biomes"]=initial};
    }
    public void refresh_samples(Resource owner,Resource terrain,GArray indices,Settings noises)
    {
        var fields=terrain.Get("biome_data").AsGodotDictionary();if(fields.Count==0)return;var grid=new Grid(terrain);int n=grid.N;var shore=Get(grid.Water,"shore_distance",Array.Empty<float>()).AsFloat32Array();
        var weights=fields["weights"].AsGodotDictionary();var buffers=new Dictionary<string,float[]>();foreach(var value in weights)buffers[value.Key.AsString()]=value.Value.AsFloat32Array();
        var slopes=fields["slope"].AsFloat32Array();var temperatures=fields["temperature"].AsFloat32Array();var humidities=fields["humidity"].AsFloat32Array();var roughness=fields["roughness"].AsFloat32Array();var sampler=new TerrainBiomeSampler(owner,noises);var features=new Settings {["geology"]=grid.Geology};
        foreach(var value in indices)
        {
            int index=value.AsInt32();if(index<0||index>=n*n)continue;var p=grid.Position(index%n,index/n);
            foreach(var sample in sampler.Sample(new Vector2(p.X,p.Z),p.Y,slopes[index],temperatures[index],humidities[index],shore.Length==n*n?shore[index]:100000,roughness[index],index,n,features))buffers[sample.Key][index]=(float)sample.Value;
        }
        foreach(var pair in buffers)weights[pair.Key]=pair.Value;
    }
}
