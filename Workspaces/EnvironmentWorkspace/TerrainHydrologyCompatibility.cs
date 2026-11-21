using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainHydrologyOperations
{
    private static Context Existing(Resource owner,Settings? cancellation=null)=>new(owner,owner.Get("_ground").AsFloat32Array(),owner.Get("_n").AsInt32(),owner.Get("_dimensions").AsVector2(),cancellation??new Settings());
    public Vector3 point(Resource owner,int index)=>Existing(owner).Point(index);
    public int cell(Resource owner,Vector2 point)=>Existing(owner).Cell(point);
    public double sample(Resource owner,float[] values,Vector2 point)=>Existing(owner).Sample(values,point);
    public void push(GArray heap,Vector2 item)
    {
        heap.Add(item);int index=heap.Count-1;while(index>0){int parent=(index-1)>>1;var other=heap[parent].AsVector2();if(other.X<item.X||(other.X==item.X&&other.Y<=item.Y))break;heap[index]=other;index=parent;}heap[index]=item;
    }
    public Vector2 pop(GArray heap)
    {
        var result=heap[0].AsVector2();var tail=heap[heap.Count-1].AsVector2();heap.RemoveAt(heap.Count-1);if(heap.Count==0)return result;int index=0;
        while(index*2+1<heap.Count){int child=index*2+1;var next=heap[child].AsVector2();if(child+1<heap.Count){var right=heap[child+1].AsVector2();if(right.X<next.X||(right.X==next.X&&right.Y<next.Y)){child++;next=right;}}if(tail.X<next.X||(tail.X==next.X&&tail.Y<=next.Y))break;heap[index]=next;index=child;}heap[index]=tail;return result;
    }
    public Settings flood_water(Resource owner,int[] seeds,double level,float[] ground,float[] levels,byte[] kinds,int kind,Settings cancellation)
    {Existing(owner,cancellation).Flood(seeds,level,ground,levels,kinds,(byte)kind);return new Settings {["levels"]=levels,["kinds"]=kinds};}
    public GArray rivers(Resource owner,float[] source,float[] filled,int[] downstream,float[] accumulation,float[] levels,Settings cancellation)
    {var result=new GArray();foreach(var path in Existing(owner,cancellation).Rivers(source,filled,downstream,accumulation,levels))result.Add(path);return result;}
    public Settings carve(Resource owner,Settings path,float[] source,float[] delta,float[] levels,Vector2[] flow,GArray waterfalls)
    {Existing(owner).Carve(path,source,delta,levels,flow,waterfalls);return new Settings {["delta"]=delta,["levels"]=levels,["flow"]=flow};}
    public float[] distance(Resource owner,byte[] wet,bool toWater,Settings cancellation)=>Existing(owner,cancellation).Distance(wet,toWater);
    public void build_water(Resource owner,GArray paths,float[] ground,float[] levels,byte[] kinds,Settings cancellation)
    {var context=Existing(owner,cancellation);context.BuildWater(paths.Select(value=>value.AsGodotDictionary()).ToList(),ground,levels,kinds);context.Publish();}
}
