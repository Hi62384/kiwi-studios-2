using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentClimateOperations
{
    public Settings procedural_state(Resource source,double sceneTime)
    {double interval=Math.Max(1,D(source,"weather_interval"));long slot=(long)Math.Floor(sceneTime/interval);double phase=Mod(sceneTime,interval),transition=D(source,"weather_transition"),blend=transition<=0?1:Mathf.SmoothStep(0.0,1.0,Math.Clamp(phase/transition,0,1));return blend_weather(procedural_pick(source,slot-1),procedural_pick(source,slot),blend);}
    public Settings procedural_pick(Resource source,long slot)
    {using var rng=new RandomNumberGenerator();using var values=new GArray {source.Get("weather_seed"),slot};rng.Seed=unchecked((uint)GD.Hash(values));double roll=rng.Randf(),storm=D(source,"storm_probability"),rain=D(source,"rain_probability"),snow=D(source,"snow_probability");int selected=roll<storm?3:roll<storm+rain?2:roll<storm+rain+snow?4:roll<.65?1:0;return scaled_weather(source,selected,.6+rng.Randf()*.4);}
    public Settings scheduled_state(Resource source,double sceneTime)
    {
        var previous=weather_value(source,I(source,"weather"));previous["weather_intensity"]=source.Get("weather_intensity");foreach(var entry in source.Get("schedule").AsGodotArray().Select(value=>value.AsGodotDictionary()).OrderBy(entry=>Get(entry,"time",0.0).AsDouble())){double start=entry["time"].AsDouble(),duration=Get(entry,"duration",1.0).AsDouble();int index=Array.IndexOf(Weather,Get(entry,"weather","Clear").AsString());if(index<0)continue;var target=scaled_weather(source,index,Get(entry,"intensity",1.0).AsDouble());if(sceneTime<start)return previous;if(sceneTime<start+duration)return blend_weather(previous,target,Mathf.SmoothStep(0.0,1.0,(sceneTime-start)/duration));previous=target;}return previous;
    }
    public Settings weather_value(Resource source,int index)
    {
        var result=new Settings {["weather"]=Weather[index],["precipitation"]=0.0,["rain"]=0.0,["snow"]=0.0,["fog"]=0.0,["dust"]=0.0,["cloud_coverage"]=source.Get("cloud_coverage"),["weather_intensity"]=source.Get("weather_intensity")};switch(index){case 1:result["cloud_coverage"]=.65;break;case 2:result["precipitation"]=1.0;result["rain"]=1.0;result["cloud_coverage"]=.8;break;case 3:result["precipitation"]=1.0;result["rain"]=1.0;result["cloud_coverage"]=1.0;result["fog"]=.2;break;case 4:result["precipitation"]=1.0;result["snow"]=1.0;result["cloud_coverage"]=.82;break;case 5:result["fog"]=1.0;result["cloud_coverage"]=.9;break;case 6:result["dust"]=1.0;result["cloud_coverage"]=.55;break;}return result;
    }
    public Settings scaled_weather(Resource source,int index,double intensity)
    {var result=weather_value(source,index);intensity=Math.Clamp(intensity,0,1);result["weather_intensity"]=intensity;foreach(string key in new[]{"precipitation","rain","snow","fog","dust"})result[key]=Get(result,key,0.0).AsDouble()*intensity;return result;}
    public Settings blend_weather(Settings from,Settings to,double weight)
    {var result=from.Duplicate(true);weight=Math.Clamp(weight,0,1);foreach(string key in new[]{"precipitation","rain","snow","fog","dust","weather_intensity","cloud_coverage"})if(to.TryGetValue(key,out var value))result[key]=Mathf.Lerp(Get(result,key,0.0).AsDouble(),value.AsDouble(),weight);if(weight>=.5)foreach(string key in new[]{"weather","season"})if(to.TryGetValue(key,out var value))result[key]=value;return result;}
    public double point_to_segment(Vector2 point,Vector2 a,Vector2 b)=>point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,a,b));
    public double region_weight(Settings region,Vector3 point)
    {
        if(!Get(region,"enabled",true).AsBool())return 0;var delta=point-Get(region,"center",Vector3.Zero).AsVector3();var size=Get(region,"size",Vector3.One).AsVector3();bool inside=false;double edge=0;switch(Get(region,"shape","Sphere").AsString())
        {
            case "Sphere":edge=size.X*.5-delta.Length();inside=edge>=0;break;
            case "Ellipsoid":var normalized=new Vector3((float)(delta.X/Math.Max(.001,size.X*.5)),(float)(delta.Y/Math.Max(.001,size.Y*.5)),(float)(delta.Z/Math.Max(.001,size.Z*.5)));inside=normalized.Length()<=1;edge=(1-normalized.Length())*Math.Min(size.X,Math.Min(size.Y,size.Z))*.5;break;
            case "Box":var margin=size*.5f-delta.Abs();inside=margin.X>=0&&margin.Y>=0&&margin.Z>=0;edge=Math.Min(margin.X,Math.Min(margin.Y,margin.Z));break;
            case "Polygon":var polygon=Get(region,"polygon",Array.Empty<Vector2>()).AsVector2Array();var horizontal=new Vector2(point.X,point.Z);inside=Geometry2D.IsPointInPolygon(horizontal,polygon);if(inside){edge=double.PositiveInfinity;for(int index=0;index<polygon.Length;index++)edge=Math.Min(edge,point_to_segment(horizontal,polygon[index],polygon[(index+1)%polygon.Length]));}break;
        }
        if(!inside)return 0;double blend=Get(region,"blend_distance",0.0).AsDouble();return blend<=0?1:Mathf.SmoothStep(0.0,blend,edge);
    }
}
