using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainHydrologyOperations : RefCounted
{
    private readonly EnvironmentDataHash _hash=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private const double Dry=-1e20;
    private static readonly Vector2I[] Directions={new(-1,0),new(1,0),new(0,-1),new(0,1),new(1,-1),new(-1,1)};
    public long geometry_signature(Resource owner)
    {using var values=new GArray {2};foreach(string field in new[]{"enabled","automatic_rivers","catchment_threshold","river_width","river_depth","flow_speed","rainfall","rainfall_variation","minimum_river_slope","maximum_rivers","mesh_vertex_budget","waterfall_drop","automatic_lakes","lake_minimum_depth","ocean_enabled","sea_level","moisture_radius","manual_rivers","manual_lakes"})values.Add(owner.Get(field));return _hash.value(values);}
    public long signature(Resource owner)
    {using var values=new GArray {geometry_signature(owner)};foreach(string field in new[]{"flow_speed","water_color","roughness","wave_strength","wave_scale","wave_direction","material_asset","water_physics","water_density","water_drag","foam_color","foam_amount","waterfall_spray","spray_per_fall","spray_size","spray_lifetime"})values.Add(owner.Get(field));return unchecked((uint)GD.Hash(values));}
    public string[] validate(Resource owner)
    {
        double D(string key)=>owner.Get(key).AsDouble();var errors=new List<string>();
        if(!double.IsFinite(D("water_density"))||D("water_density")<=0||!double.IsFinite(D("water_drag"))||D("water_drag")<0)errors.Add("Water density must be positive and drag must be nonnegative finite values.");
        if(!double.IsFinite(D("foam_amount"))||!double.IsFinite(D("spray_size"))||D("spray_size")<=0||!double.IsFinite(D("spray_lifetime"))||D("spray_lifetime")<=0)errors.Add("Waterfall appearance values must be finite with positive size and lifetime.");
        foreach(string name in new[]{"catchment_threshold","river_width","river_depth","flow_speed","rainfall","rainfall_variation","minimum_river_slope","waterfall_drop","lake_minimum_depth","sea_level","moisture_radius","roughness","wave_strength","wave_scale"})if(!double.IsFinite(D(name))){errors.Add("Water generation values must be finite.");break;}
        foreach(var entry in owner.Get("manual_rivers").AsGodotArray()){var points=Get(entry.AsGodotDictionary(),"points",Array.Empty<Vector3>()).AsVector3Array();if(points.Length<2)errors.Add("River paths need at least two points.");foreach(var point in points)if(!point.IsFinite()){errors.Add("River path coordinates must be finite.");break;}}return errors.ToArray();
    }
    private sealed partial class Context
    {
        internal readonly Resource Owner;
        internal readonly Settings Cancellation;
        internal readonly int N;
        internal readonly Vector2 Dimensions,Spacing;
        internal readonly float[] Ground;
        internal readonly Settings Parameters=new();
        internal readonly List<Vector3> Vertices=new(),Normals=new();
        internal readonly List<Vector2> Uv=new(),Uv2=new();
        internal readonly List<Color> Colors=new();
        internal readonly List<int> Indices=new();
        internal string MeshError="";
        internal Context(Resource owner,float[] ground,int n,Vector2 dimensions,Settings cancellation)
        {
            Owner=owner;Ground=ground;N=n;Dimensions=dimensions;Spacing=dimensions/Math.Max(1,n-1);Cancellation=cancellation;
            foreach(var property in owner.GetPropertyList()){string name=property["name"].AsString();if((property["usage"].AsInt64()&(long)PropertyUsageFlags.Storage)!=0&&name!="script")Parameters[name]=owner.Get(name);}
        }
        internal double D(string key)=>Parameters[key].AsDouble();
        internal int I(string key)=>Parameters[key].AsInt32();
        internal bool B(string key)=>Parameters[key].AsBool();
        internal bool Cancelled()=>Get(Cancellation,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",Cancellation).AsBool();
        internal Vector3 Point(int index)=>new((float)((index%N/(double)Math.Max(1,N-1)-.5)*Dimensions.X),Ground[index],(float)((index/N/(double)Math.Max(1,N-1)-.5)*Dimensions.Y));
        internal int Cell(Vector2 point){var p=(point/Dimensions+Vector2.One*.5f)*(N-1);var cell=(Vector2I)p.Round();return Math.Clamp(cell.X,0,N-1)+Math.Clamp(cell.Y,0,N-1)*N;}
        internal double Sample(float[] values,Vector2 point)
        {var p=((point/Dimensions+Vector2.One*.5f)*(N-1)).Clamp(Vector2.Zero,Vector2.One*(N-1));var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;int right=Math.Min(cell.X+1,N-1),down=Math.Min(cell.Y+1,N-1);return Mathf.Lerp(Mathf.Lerp((double)values[cell.X+cell.Y*N],values[right+cell.Y*N],f.X),Mathf.Lerp((double)values[cell.X+down*N],values[right+down*N],f.X),f.Y);}
        internal Settings MeshData()=>new() {["vertices"]=Vertices.ToArray(),["normals"]=Normals.ToArray(),["uv"]=Uv.ToArray(),["uv2"]=Uv2.ToArray(),["colors"]=Colors.ToArray(),["indices"]=Indices.ToArray()};
        internal void Publish(Settings? mesh=null)
        {mesh??=MeshData();Owner.Set("_n",N);Owner.Set("_dimensions",Dimensions);Owner.Set("_spacing",Spacing);foreach(string name in new[]{"vertices","normals","uv","uv2","colors","indices"})Owner.Set("_"+name,mesh[name]);Owner.Set("_mesh_error",MeshError);}

    }
    public Settings generate(Resource owner,float[] source,int n,Vector2 dimensions,long seed,Settings cancellation)
    {
        ulong started=Time.GetTicksUsec();var context=new Context(owner,source,n,dimensions,cancellation);owner.Set("_n",n);owner.Set("_dimensions",dimensions);owner.Set("_spacing",context.Spacing);owner.Set("_ground",source);int count=checked(n*n);var filled=(float[])source.Clone();var downstream=new int[count];Array.Fill(downstream,-1);var visited=new byte[count];var order=new List<int>();var heap=new PriorityQueue<int,(float,int)>();var accumulation=new float[count];var levels=new float[count];Array.Fill(levels,(float)Dry);var kinds=new byte[count];var delta=new float[count];var flow=new Vector2[count];var warnings=new List<string>();
        if(!context.B("enabled"))return new Settings {["delta"]=delta,["levels"]=levels,["depth"]=new float[count],["flow"]=flow,["paths"]=new GArray(),["mesh"]=new Settings(),["warnings"]=Array.Empty<string>(),["cancelled"]=false,["milliseconds"]=0.0};
        var errors=validate(owner);if(errors.Length>0)return new Settings {["error"]=string.Join("\n",errors)};
        var rivers=context.Parameters["manual_rivers"].AsGodotArray();var lakes=context.Parameters["manual_lakes"].AsGodotArray();
        foreach(var entry in rivers)foreach(var point in Get(entry.AsGodotDictionary(),"points",Array.Empty<Vector3>()).AsVector3Array())if(Math.Abs(point.X)>dimensions.X*.5||Math.Abs(point.Z)>dimensions.Y*.5)return new Settings {["error"]="River control points must remain inside their terrain."};
        foreach(var entry in lakes){var center=Get(entry.AsGodotDictionary(),"center",Vector2.Zero).AsVector2();if(Math.Abs(center.X)>dimensions.X*.5||Math.Abs(center.Y)>dimensions.Y*.5)return new Settings {["error"]="Lake centers must remain inside their terrain."};}
        for(int z=0;z<n;z++)for(int x=0;x<n;x++){if(x!=0&&z!=0&&x!=n-1&&z!=n-1)continue;int index=x+z*n;visited[index]=1;heap.Enqueue(index,(source[index],index));}
        while(heap.Count>0)
        {
            if(order.Count%128==0&&context.Cancelled())return new Settings {["cancelled"]=true};int index=heap.Dequeue();order.Add(index);var point=new Vector2I(index%n,index/n);
            foreach(var direction in Directions){var next=point+direction;if(next.X<0||next.Y<0||next.X>=n||next.Y>=n)continue;int neighbor=next.X+next.Y*n;if(visited[neighbor]!=0)continue;visited[neighbor]=1;downstream[neighbor]=index;filled[neighbor]=Math.Max(source[neighbor],filled[index]);heap.Enqueue(neighbor,(filled[neighbor],neighbor));}
        }
        using var rain=new FastNoiseLite {Seed=unchecked((int)(seed+197)),Frequency=.1f};
        for(int index=0;index<count;index++){int x=index%n,z=index/n;double area=(double)context.Spacing.X*context.Spacing.Y*(x==0||x==n-1?.5:1)*(z==0||z==n-1?.5:1);var point=context.Point(index);accumulation[index]=(float)(Math.Max(0,context.D("rainfall"))*area*Math.Max(0,1+rain.GetNoise2Dv(new Vector2(point.X,point.Z))*Math.Clamp(context.D("rainfall_variation"),0,1)));}
        for(int position=order.Count-1;position>=0;position--){int index=order[position],parent=downstream[index];if(parent>=0)accumulation[parent]+=accumulation[index];}
        if(context.B("ocean_enabled")){var seeds=order.Where(index=>(index%n==0||index/n==0||index%n==n-1||index/n==n-1)&&source[index]<context.D("sea_level")).ToArray();context.Flood(seeds,context.D("sea_level"),source,levels,kinds,1);}
        if(context.B("automatic_lakes"))for(int index=0;index<count;index++)if(source[index]<filled[index]-Math.Max(.01,context.D("lake_minimum_depth"))&&levels[index]<filled[index]-.0001)context.Flood(new[]{index},filled[index],source,levels,kinds,2);
        foreach(var entry in lakes){var lake=entry.AsGodotDictionary();if(!Get(lake,"enabled",true).AsBool())continue;int index=context.Cell(Get(lake,"center",Vector2.Zero).AsVector2());double level=Get(lake,"level",0.0).AsDouble();if(source[index]>=level){warnings.Add("A lake center is above its water level; move it into a basin or raise the level.");continue;}context.Flood(new[]{index},level,source,levels,kinds,2);}
        if(context.Cancelled())return new Settings {["cancelled"]=true};var paths=context.B("automatic_rivers")?context.Rivers(source,filled,downstream,accumulation,levels):new List<Settings>();
        foreach(var entry in rivers)
        {
            var river=entry.AsGodotDictionary();if(!Get(river,"enabled",true).AsBool())continue;var points=Get(river,"points",Array.Empty<Vector3>()).AsVector3Array();double width=Math.Max(Math.Max(context.Spacing.X,context.Spacing.Y)*1.25,Get(river,"width",context.D("river_width")).AsDouble()),depth=Math.Max(.01,Get(river,"depth",context.D("river_depth")).AsDouble());bool follow=Get(river,"follow_terrain",true).AsBool();var projected=new Vector3[points.Length];var widths=new float[points.Length];double previous=double.PositiveInfinity;
            for(int i=0;i<points.Length;i++){var point=points[i];double height=follow?context.Sample(source,new Vector2(point.X,point.Z))-depth*.35:point.Y;if(!Get(river,"allow_uphill",false).AsBool())height=Math.Min(previous,height);previous=height;projected[i]=new Vector3(point.X,(float)height,point.Z);widths[i]=(float)width;}paths.Add(new Settings {["id"]=Get(river,"id","manual"),["points"]=projected,["widths"]=widths,["depth"]=depth,["automatic"]=false});
        }
        int maxRivers=Math.Clamp(context.I("maximum_rivers"),1,256);if(paths.Count>maxRivers){warnings.Add("River count reached its generation budget.");paths.RemoveRange(maxRivers,paths.Count-maxRivers);}var waterfalls=new GArray();
        foreach(var path in paths){if(context.Cancelled())return new Settings {["cancelled"]=true};foreach(var point in path["points"].AsVector3Array()){int index=context.Cell(new Vector2(point.X,point.Z));if(source[index]<point.Y-.001&&levels[index]<point.Y-.001)context.Flood(new[]{index},point.Y,source,levels,kinds,2);}context.Carve(path,source,delta,levels,flow,waterfalls);}
        var ground=(float[])source.Clone();for(int index=0;index<count;index++)ground[index]+=delta[index];var depthField=new float[count];var wet=new byte[count];bool anyWater=false;
        for(int index=0;index<count;index++)if(levels[index]>Dry*.5){depthField[index]=Math.Max(0,levels[index]-ground[index]);wet[index]=depthField[index]>.0001?(byte)1:(byte)0;anyWater|=wet[index]!=0;}
        var distanceWet=context.Distance(wet,true);var distanceDry=context.Distance(wet,false);var shore=new float[count];var moisture=new float[count];for(int index=0;index<count;index++){shore[index]=wet[index]!=0?-distanceDry[index]:distanceWet[index];moisture[index]=anyWater?(float)Math.Exp(-Math.Max(0,shore[index])/Math.Max(.01,context.D("moisture_radius"))):0;}
        context.BuildWater(paths,ground,levels,kinds);var mesh=context.MeshData();context.Publish(mesh);if(context.MeshError.Length>0)return new Settings {["error"]=context.MeshError};var pathValues=new GArray();foreach(var path in paths)pathValues.Add(path);
        return new Settings {["delta"]=delta,["ground"]=ground,["filled"]=filled,["downstream"]=downstream,["accumulation"]=accumulation,["levels"]=levels,["depth"]=depthField,["flow"]=flow,["shore_distance"]=shore,["moisture"]=moisture,["body_kind"]=kinds,["paths"]=pathValues,["waterfalls"]=waterfalls,["mesh"]=mesh,["warnings"]=warnings.ToArray(),["cancelled"]=context.Cancelled(),["error"]="",["milliseconds"]=(Time.GetTicksUsec()-started)/1000.0};
    }
}
