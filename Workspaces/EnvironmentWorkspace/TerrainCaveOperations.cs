using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainCaveOperations : RefCounted
{
    private readonly EnvironmentDataHash _hash=new();
    public long signature(Resource cave)
    {using var values=new GArray();foreach(string field in new[]{"cave_id","title","enabled","seed","radius","radius_variation","junction_smoothing","roughness","detail_frequency","paths","chambers","edits"})values.Add(cave.Get(field));return _hash.value(values);}
    public string[] validate(Resource cave)
    {
        var field=new TerrainCaveField(cave);var errors=new List<string>();if(field.Radius<=0||!double.IsFinite(field.Radius))errors.Add("Cave radius must be positive and finite.");
        foreach(var path in field.Paths){if(path.Length<2)errors.Add("Cave tunnel paths need at least two points.");foreach(var point in path)if(!point.IsFinite()){errors.Add("Cave points must be finite.");break;}}
        foreach(var chamber in field.Chambers)if(!chamber.IsFinite()||chamber.W<=0)errors.Add("Cave chambers need finite centers and a positive radius.");return errors.ToArray();
    }
    public void prepare(Resource cave)=>cave.Set("_noise",new FastNoiseLite {Seed=unchecked((int)cave.Get("seed").AsInt64()),Frequency=(float)Math.Max(.001,cave.Get("detail_frequency").AsDouble())});
    public double segment_radius(Resource cave,int index)=>new TerrainCaveField(cave).SegmentRadius(index);
    public Aabb bounds(Resource cave)=>new TerrainCaveField(cave).Bounds();
    public double distance(Resource cave,Vector3 point)=>new TerrainCaveField(cave).Distance(point);
    public double raw_distance(Resource cave,Vector3 point)=>new TerrainCaveField(cave).Raw(point);
    public double smooth_min(double a,double b,double width)=>TerrainCaveField.SmoothMin(a,b,width);
    public long local_signature(Resource cave,Aabb region)
    {
        var field=new TerrainCaveField(cave);using var values=new GArray {cave.Get("enabled"),field.Seed,field.Radius,field.Variation,field.Smoothing,field.Roughness,field.Frequency};
        double margin=Math.Max(.05,field.Radius)*(1+Math.Clamp(field.Variation,0,.5))+Math.Abs(field.Roughness)+Math.Max(0,field.Smoothing);
        foreach(var path in field.Paths)for(int index=0;index<path.Length-1;index++)if(new Aabb(path[index],Vector3.Zero).Expand(path[index+1]).Grow((float)margin).Intersects(region))values.Add(new GArray {path[index],path[index+1],field.SegmentRadius(index),field.SegmentRadius(index+1)});
        foreach(var chamber in field.Chambers){var center=new Vector3(chamber.X,chamber.Y,chamber.Z);float radius=(float)(chamber.W+Math.Abs(field.Roughness)+field.Smoothing);if(new Aabb(center-Vector3.One*radius,Vector3.One*radius*2).Intersects(region))values.Add(chamber);}
        foreach(var edit in field.Edits){var center=TerrainCaveField.Get(edit,"center",Vector3.Zero).AsVector3();float radius=(float)(Math.Max(.01,TerrainCaveField.Get(edit,"radius",1.0).AsDouble())+field.Smoothing);if(new Aabb(center-Vector3.One*radius,Vector3.One*radius*2).Intersects(region))values.Add(edit);}
        return _hash.value(values);
    }
    public Resource network(Vector3 entrance,double depth,double length,int branches,long seed)
    {
        var cave=new KiwiTerrainCave();cave.Set("seed",seed);using var rng=new RandomNumberGenerator {Seed=unchecked((ulong)seed)};var main=new Vector3[7];
        for(int index=0;index<7;index++){double t=index/6.0;main[index]=entrance+new Vector3((float)(Math.Sin(t*Math.PI)*rng.RandfRange((float)(-length*.15),(float)(length*.15))),(float)(-depth*Mathf.SmoothStep(0.0,.8,t)),(float)(length*t));}
        var paths=cave.Get("paths").AsGodotArray();paths.Add(main);var chambers=new List<Vector4>();
        for(int branch=0;branch<Math.Clamp(branches,0,12);branch++){var junction=main[2+branch%4];var direction=new Vector3(branch%2==0?-1:1,rng.RandfRange(-.3f,.1f),rng.RandfRange(.2f,.7f)).Normalized();var path=new[]{junction,junction+direction*(float)length*.25f,junction+direction*(float)length*.5f+new Vector3(0,-1,0)};paths.Add(path);var end=path[^1];chambers.Add(new Vector4(end.X,end.Y,end.Z,(float)(cave.Get("radius").AsDouble()*1.5)));}
        var finish=main[^1];chambers.Add(new Vector4(finish.X,finish.Y,finish.Z,(float)(cave.Get("radius").AsDouble()*1.8)));cave.Set("chambers",chambers.ToArray());return cave;
    }
}
