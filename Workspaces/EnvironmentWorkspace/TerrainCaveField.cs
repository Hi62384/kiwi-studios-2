using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

internal sealed class TerrainCaveField
{
    internal readonly Vector3[][] Paths;
    internal readonly Vector4[] Chambers;
    internal readonly Settings[] Edits;
    internal readonly double Radius,Variation,Smoothing,Roughness,Frequency;
    internal readonly long Seed;
    internal readonly FastNoiseLite? Noise;
    internal static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    internal TerrainCaveField(Resource cave)
    {
        Radius=cave.Get("radius").AsDouble();Variation=cave.Get("radius_variation").AsDouble();Smoothing=cave.Get("junction_smoothing").AsDouble();Roughness=cave.Get("roughness").AsDouble();Frequency=cave.Get("detail_frequency").AsDouble();Seed=cave.Get("seed").AsInt64();Noise=cave.Get("_noise").As<FastNoiseLite>();
        Paths=cave.Get("paths").AsGodotArray().Select(value=>value.AsVector3Array()).ToArray();Chambers=cave.Get("chambers").AsVector4Array();Edits=cave.Get("edits").AsGodotArray().Select(value=>value.AsGodotDictionary()).ToArray();
    }
    internal double SegmentRadius(int index)=>Math.Max(.05,Radius*(1+Math.Clamp(Variation,0,.5)*Math.Sin(Seed*1.713+index*2.399)));
    internal static double SmoothMin(double a,double b,double width)
    {if(!double.IsFinite(a))return b;if(width<=.00001)return Math.Min(a,b);double blend=Math.Clamp(.5+.5*(b-a)/width,0,1);return Mathf.Lerp(b,a,blend)-width*blend*(1-blend);}
    internal Aabb Bounds()
    {
        var bounds=new Aabb();bool first=true;double margin=Math.Max(.05,Radius)*(1+Math.Clamp(Variation,0,.5))+Math.Abs(Roughness)+Math.Max(0,Smoothing);
        void Add(Aabb box){bounds=first?box:bounds.Merge(box);first=false;}
        foreach(var path in Paths)foreach(var point in path)Add(new Aabb(point-Vector3.One*(float)margin,Vector3.One*(float)(margin*2)));
        foreach(var chamber in Chambers){var center=new Vector3(chamber.X,chamber.Y,chamber.Z);var size=Vector3.One*(float)(chamber.W+Math.Abs(Roughness)+Math.Max(0,Smoothing));Add(new Aabb(center-size,size*2));}
        foreach(var edit in Edits){var center=Get(edit,"center",Vector3.Zero).AsVector3();var size=Vector3.One*(float)Math.Max(.01,Get(edit,"radius",1.0).AsDouble());Add(new Aabb(center-size,size*2));}return bounds;
    }
    internal double Raw(Vector3 point)
    {
        double distance=double.PositiveInfinity;
        foreach(var path in Paths)for(int index=0;index<path.Length-1;index++)
        {var a=path[index];var b=path[index+1];var direction=b-a;double t=Math.Clamp((point-a).Dot(direction)/Math.Max(.000001,direction.LengthSquared()),0,1),radius=Mathf.Lerp(SegmentRadius(index),SegmentRadius(index+1),t),sample=point.DistanceTo(a+direction*(float)t)-radius;distance=SmoothMin(distance,sample,Math.Max(0,Smoothing));}
        foreach(var chamber in Chambers)distance=SmoothMin(distance,point.DistanceTo(new Vector3(chamber.X,chamber.Y,chamber.Z))-chamber.W,Math.Max(0,Smoothing));
        if(double.IsFinite(distance)&&Noise!=null&&Roughness!=0)distance+=Noise.GetNoise3Dv(point)*Roughness;
        foreach(var edit in Edits)
        {
            if(Get(edit,"smooth",false).AsBool())continue;double sample=point.DistanceTo(Get(edit,"center",Vector3.Zero).AsVector3())-Math.Max(.01,Get(edit,"radius",1.0).AsDouble());
            double changed=Get(edit,"fill",false).AsBool()?Math.Max(distance,-sample):SmoothMin(distance,sample,Math.Max(0,Smoothing));distance=double.IsFinite(distance)?Mathf.Lerp(distance,changed,Math.Clamp(Get(edit,"strength",1.0).AsDouble(),0,1)):changed;
        }
        return distance;
    }
    internal double Distance(Vector3 point)
    {
        double result=Raw(point);if(!double.IsFinite(result))return result;double weight=0,step=0;
        foreach(var edit in Edits)
        {
            if(!Get(edit,"smooth",false).AsBool())continue;double radius=Math.Max(.01,Get(edit,"radius",1.0).AsDouble()),distance=point.DistanceTo(Get(edit,"center",Vector3.Zero).AsVector3())/radius;if(distance>=1)continue;
            double influence=Math.Pow(1-distance,2)*Math.Clamp(Get(edit,"strength",1.0).AsDouble(),0,1);weight=1-(1-weight)*(1-influence);step=Math.Max(step,radius*.15);
        }
        if(weight<=0)return result;var x=new Vector3((float)step,0,0);var y=new Vector3(0,(float)step,0);var z=new Vector3(0,0,(float)step);
        double average=(Raw(point+x)+Raw(point-x)+Raw(point+y)+Raw(point-y)+Raw(point+z)+Raw(point-z))/6;return Mathf.Lerp(result,average,weight);
    }
}
