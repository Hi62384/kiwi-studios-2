using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RoadEditingOperations : RefCounted
{
    private readonly WorldSourceOperations _sources=new();
    private static GArray Roads(Resource source)=>source.Get("roads").AsGodotArray();
    private static Settings Nodes(Resource source)=>source.Get("nodes").AsGodotDictionary();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings Result(Resource source,int index)=>new() {["source"]=source,["index"]=index,["error"]=""};
    public Settings error(string text)=>new() {["source"]=default,["error"]=text};
    public Settings result(Resource source,int index)=>Result(source,index);
    public Settings reverse(Resource source,int index)
    {if(index<0||index>=Roads(source).Count)return error("Choose an existing road.");var next=_sources.copy(source);var road=Roads(next)[index].AsGodotDictionary();var points=road["points"].AsVector3Array();Array.Reverse(points);road["points"]=points;string from=road["from"].AsString();road["from"]=road["to"];road["to"]=from;return Result(next,index);}
    public Settings remove_point(Resource source,int index,int point)
    {
        if(index<0||index>=Roads(source).Count)return error("Choose an existing road.");var next=_sources.copy(source);var road=Roads(next)[index].AsGodotDictionary();var points=new List<Vector3>(road["points"].AsVector3Array());if(points.Count<3||point<0||point>=points.Count)return error("A road needs at least two control points.");bool endpoint=point==0||point==points.Count-1;points.RemoveAt(point);road["points"]=points.ToArray();if(endpoint){string id=Guid.NewGuid().ToString("N");Nodes(next)[id]=point==0?points[0]:points[^1];road[point==0?"from":"to"]=id;}cleanup(next);return Result(next,index);
    }
    public Settings split(Resource source,int index,int point)
    {
        if(index<0||index>=Roads(source).Count)return error("Choose an existing road.");var next=_sources.copy(source);var roads=Roads(next);var road=roads[index].AsGodotDictionary();var points=new List<Vector3>(road["points"].AsVector3Array());if(point<1||point>=points.Count-1){int middle=points.Count/2;points.Insert(middle,points[middle-1].Lerp(points[middle],.5f));point=middle;}road["source_family"]=Get(road,"source_family",road["id"]);string node=Guid.NewGuid().ToString("N");Nodes(next)[node]=points[point];var second=road.Duplicate(true);second["id"]=Guid.NewGuid().ToString("N");second["name"]=Get(road,"name","Road").AsString()+" · B";second["from"]=node;second["points"]=points.Skip(point).ToArray();road["to"]=node;road["points"]=points.Take(point+1).ToArray();roads.Insert(index+1,second);return Result(next,index);
    }
    public Settings join(Resource source,int index,int other)
    {
        if(index<0||other<0||index>=Roads(source).Count||other>=Roads(source).Count||index==other)return error("Choose two different roads.");var next=_sources.copy(source);var roads=Roads(next);var first=roads[index].AsGodotDictionary();var second=roads[other].AsGodotDictionary().Duplicate(true);var a=new List<Vector3>(first["points"].AsVector3Array());var b=second["points"].AsVector3Array();if(Get(first,"mode","Ground").AsString()!=Get(second,"mode","Ground").AsString())return error("Join roads with the same ground, bridge or tunnel mode.");if(a[^1].DistanceTo(b[^1])<a[^1].DistanceTo(b[0])){Array.Reverse(b);string from=second["from"].AsString();second["from"]=second["to"];second["to"]=from;}if(a[^1].DistanceTo(b[0])>.25)return error("The end of the selected road must meet an endpoint of the other road.");a[^1]=(a[^1]+b[0])*.5f;a.AddRange(b.Skip(1));first["points"]=a.ToArray();first["to"]=second["to"];roads.RemoveAt(other);cleanup(next);return Result(next,other<index?index-1:index);
    }
    public void cleanup(Resource source)
    {var used=new HashSet<string>(StringComparer.Ordinal);foreach(var value in Roads(source)){var road=value.AsGodotDictionary();used.Add(road["from"].AsString());used.Add(road["to"].AsString());}var nodes=Nodes(source);foreach(var key in nodes.Keys.ToArray())if(!used.Contains(key.AsString()))nodes.Remove(key);}
}
