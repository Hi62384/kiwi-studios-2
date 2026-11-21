using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class PixelObjectSegmenterKernel:RefCounted
{
    private RefCounted? _fieldBridge;private PixelEdgeFieldKernel _field=null!;
    private int[] _labels=Array.Empty<int>(),_areas=Array.Empty<int>();private Color[] _means=Array.Empty<Color>();
    private readonly List<Dictionary<int,double>> _graph=new();private readonly Dictionary<int,int> _background=new();private readonly HashSet<int> _borderRegions=new();
    private float[] _distances=Array.Empty<float>(),_backgroundDistances=Array.Empty<float>(),_foregroundTravel=Array.Empty<float>(),_backgroundTravel=Array.Empty<float>();private int _lastSeed=-1;
    internal static double Difference(Color a,Color b)=>Math.Max(Math.Abs(a.A-b.A),new Vector3(a.R-b.R,a.G-b.G,a.B-b.B).Length()/Math.Sqrt(3));
    internal static int ColorKey(Color color)=>Math.Clamp((int)(color.R*7),0,7)+Math.Clamp((int)(color.G*7),0,7)*8+Math.Clamp((int)(color.B*7),0,7)*64;
    public Settings build(Image image,Rect2I domain)
    {
        _graph.Clear();_background.Clear();_borderRegions.Clear();_lastSeed=-1;_fieldBridge=new KiwiPixelEdgeField();_fieldBridge.Call("build",image,domain,384);_field=_fieldBridge.Get("_kernel").As<PixelEdgeFieldKernel>();var size=_field.Size;int count=size.X*size.Y;_labels=new int[count];Array.Fill(_labels,-1);var means=new List<Color>();var areas=new List<int>();var colors=_field.Colors;var queue=new List<int>();for(int start=0;start<count;start++){if(_labels[start]>=0)continue;int id=means.Count;queue.Clear();queue.Add(start);_labels[start]=id;var sum=new Color(0,0,0,0);var tile=new Vector2I(start%size.X,start/size.X)/8;for(int head=0;head<queue.Count;head++){int index=queue[head];var point=new Vector2I(index%size.X,index/size.X);sum+=colors[index];foreach(int next in Adjacent(point)){var other=new Vector2I(next%size.X,next/size.X);if(_labels[next]>=0||other/8!=tile)continue;if(Difference(colors[index],colors[next])<=.09&&Difference(colors[start],colors[next])<=.12){_labels[next]=id;queue.Add(next);}}}means.Add(sum/queue.Count);areas.Add(queue.Count);_graph.Add(new Dictionary<int,double>());}_means=means.ToArray();_areas=areas.ToArray();var boundaries=new Dictionary<Vector2I,Vector2>();for(int index=0;index<count;index++){var point=new Vector2I(index%size.X,index/size.X);int a=_labels[index];if(point.X==0||point.Y==0||point.X==size.X-1||point.Y==size.Y-1){int key=ColorKey(colors[index]);_background[key]=_background.GetValueOrDefault(key)+1;_borderRegions.Add(a);}for(int direction=0;direction<2;direction++){var other=point+(direction==0?Vector2I.Right:Vector2I.Down);if(!_field.inside(other))continue;int next=other.Y*size.X+other.X,b=_labels[next];if(a==b)continue;var key=new Vector2I(Math.Min(a,b),Math.Max(a,b));boundaries[key]=boundaries.GetValueOrDefault(key)+new Vector2((float)Difference(colors[index],colors[next]),1);}}int borderSamples=0;foreach(int value in _background.Values)borderSamples+=value;var remove=new List<int>();foreach(var entry in _background)if(entry.Value<Math.Max(3,borderSamples*.05))remove.Add(entry.Key);foreach(int key in remove)_background.Remove(key);foreach(var entry in boundaries){var key=entry.Key;var boundary=entry.Value;double difference=Difference(_means[key.X],_means[key.Y]),cost=.12+boundary.X/boundary.Y*.28+difference*.18;foreach(int id in new[]{key.X,key.Y}){var color=_means[id];if(color.A<.01)cost=1.1;else if(Math.Max(color.R,Math.Max(color.G,color.B))<.14&&difference>.15)cost=Math.Max(cost,.98);}_graph[key.X][key.Y]=cost;_graph[key.Y][key.X]=cost;}var graph=new GArray();foreach(var neighbors in _graph){var row=new Settings();foreach(var pair in neighbors)row[pair.Key]=pair.Value;graph.Add(row);}var background=new Settings();foreach(var pair in _background)background[pair.Key]=pair.Value;var borders=new Settings();foreach(int id in _borderRegions)borders[id]=true;return new Settings{["field"]=_fieldBridge,["labels"]=_labels,["means"]=_means,["areas"]=_areas,["graph"]=graph,["background"]=background,["border_regions"]=borders};
    }
    public int[] adjacent(Vector2I point)
    {
        var result=new List<int>(4);var size=_field.Size;int index=point.Y*size.X+point.X;if(point.X>0)result.Add(index-1);if(point.X+1<size.X)result.Add(index+1);if(point.Y>0)result.Add(index-size.X);if(point.Y+1<size.Y)result.Add(index+size.X);return result.ToArray();
    }
    private static List<Vector2> Heap()=>new();
    public void background_costs(int seed)
    {
        _backgroundDistances=new float[_means.Length];Array.Fill(_backgroundDistances,float.PositiveInfinity);var heap=Heap();var seeds=new List<int>();foreach(int id in _borderRegions){if(_means[id].A>.01&&Difference(_means[id],_means[seed])<.035)continue;_backgroundDistances[id]=0;PixelEdgeMagnetOperations.Push(heap,new Vector2(0,id));seeds.Add(id);}while(heap.Count>0){var item=PixelEdgeMagnetOperations.Pop(heap);int id=(int)item.Y;if(item.X>_backgroundDistances[id]+.00001)continue;foreach(var edge in _graph[id]){double distance=Math.Max(item.X,edge.Value);if(distance<_backgroundDistances[edge.Key]){_backgroundDistances[edge.Key]=(float)distance;PixelEdgeMagnetOperations.Push(heap,new Vector2((float)distance,edge.Key));}}}_backgroundTravel=travel_costs(seeds.ToArray());
    }
    public float[] travel_costs(int[] seeds)
    {
        var result=new float[_means.Length];Array.Fill(result,float.PositiveInfinity);var heap=Heap();foreach(int seed in seeds){result[seed]=0;PixelEdgeMagnetOperations.Push(heap,new Vector2(0,seed));}while(heap.Count>0){var item=PixelEdgeMagnetOperations.Pop(heap);int id=(int)item.Y;if(item.X>result[id]+.000001)continue;foreach(var edge in _graph[id]){double distance=item.X+.001+Math.Pow(Math.Max(0,edge.Value-.12)*3,2);if(distance<result[edge.Key]){result[edge.Key]=(float)distance;PixelEdgeMagnetOperations.Push(heap,new Vector2((float)distance,edge.Key));}}}return result;
    }
    public bool seed_costs(Vector2 point)
    {
        var at=_field.cell(point);if(!_field.inside(at))return false;int seed=_labels[at.Y*_field.Size.X+at.X];if(_means[seed].A<.01)return false;if(seed==_lastSeed)return true;background_costs(seed);_foregroundTravel=travel_costs(new[]{seed});_lastSeed=seed;_distances=new float[_means.Length];Array.Fill(_distances,float.PositiveInfinity);_distances[seed]=0;var heap=new List<Vector2>{new(0,seed)};while(heap.Count>0){var item=PixelEdgeMagnetOperations.Pop(heap);int id=(int)item.Y;if(item.X>_distances[id]+.00001)continue;foreach(var edge in _graph[id]){double distance=Math.Max(item.X,edge.Value);if(distance<_distances[edge.Key]){_distances[edge.Key]=(float)distance;PixelEdgeMagnetOperations.Push(heap,new Vector2((float)distance,edge.Key));}}}return true;
    }
    public Settings cost_state()=>new(){["distances"]=_distances,["last_seed"]=_lastSeed,["background_distances"]=_backgroundDistances,["foreground_travel"]=_foregroundTravel,["background_travel"]=_backgroundTravel};
}
public partial class PixelObjectSegmenterOperations:RefCounted
{
    public PixelObjectSegmenterKernel create()=>new();
    public double difference(Color a,Color b)=>PixelObjectSegmenterKernel.Difference(a,b);
    public int color_key(Color color)=>PixelObjectSegmenterKernel.ColorKey(color);
    public void heap_push(GArray heap,Vector2 item){heap.Add(item);int index=heap.Count-1;while(index>0){int parent=(index-1)/2;if(heap[parent].AsVector2().X<=item.X)break;heap[index]=heap[parent];index=parent;}heap[index]=item;}
    public Vector2 heap_pop(GArray heap){var result=heap[0].AsVector2();var item=heap[heap.Count-1].AsVector2();heap.RemoveAt(heap.Count-1);if(heap.Count==0)return result;int index=0;while(index*2+1<heap.Count){int child=index*2+1;if(child+1<heap.Count&&heap[child+1].AsVector2().X<heap[child].AsVector2().X)child++;if(heap[child].AsVector2().X>=item.X)break;heap[index]=heap[child];index=child;}heap[index]=item;return result;}
}
