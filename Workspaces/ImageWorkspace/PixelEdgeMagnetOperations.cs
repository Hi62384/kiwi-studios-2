using Godot;
using System;
using System.Collections.Generic;
public partial class PixelEdgeMagnetOperations:RefCounted
{
    private static PixelEdgeFieldKernel Field(RefCounted owner)=>owner.Get("field").AsGodotObject().Get("_kernel").As<PixelEdgeFieldKernel>();
    internal static void Push(List<Vector2> heap,Vector2 item){heap.Add(item);int index=heap.Count-1;while(index>0){int parent=(index-1)/2;if(heap[parent].X<=item.X)break;heap[index]=heap[parent];index=parent;}heap[index]=item;}
    internal static Vector2 Pop(List<Vector2> heap){var result=heap[0];var item=heap[^1];heap.RemoveAt(heap.Count-1);if(heap.Count==0)return result;int index=0;while(index*2+1<heap.Count){int child=index*2+1;if(child+1<heap.Count&&heap[child+1].X<heap[child].X)child++;if(heap[child].X>=item.X)break;heap[index]=heap[child];index=child;}heap[index]=item;return result;}
    public Vector2[] follow(RefCounted owner,Vector2 point,double threshold,Vector2 direction)
    {
        var field=Field(owner);int previous=owner.Get("previous").AsInt32(),target=field.nearest(point,threshold,previous,direction);if(target<0){owner.Set("previous",-1);return Array.Empty<Vector2>();}Vector2[] Reacquire(){owner.Set("previous",target);return new[]{field.refine(target)};}if(previous<0)return Reacquire();ulong started=Time.GetTicksUsec();var parents=new Dictionary<int,int>{{previous,-1}};var queue=new List<Vector2>{new(0,previous)};var origin=field.position(previous);var destination=field.position(target);double maximum=Math.Min(160,Math.Max(24,origin.DistanceTo(point)*1.5+16));int visited=0;while(queue.Count>0&&visited<256&&Time.GetTicksUsec()-started<2000&&!parents.ContainsKey(target)){int current=(int)Pop(queue).Y;visited++;foreach(int next in field.neighbors(current,threshold)){var position=field.position(next);if(parents.ContainsKey(next)||position.DistanceTo(origin)>maximum||position.DistanceTo(Geometry2D.GetClosestPointToSegment(position,origin,destination))>24)continue;parents[next]=current;Push(queue,new Vector2(position.DistanceSquaredTo(destination),next));}}if(!parents.ContainsKey(target))return Reacquire();var path=new List<Vector2>();for(int current=target;current>=0;current=parents[current]){if(path.Count>=128||Time.GetTicksUsec()-started>4000)return Reacquire();path.Add(field.refine(current));}path.Reverse();owner.Set("previous",target);return path.ToArray();
    }
    public Vector2[] connected(RefCounted owner,Vector2 point,double threshold)
    {
        var field=Field(owner);int seed=field.nearest(point,threshold,-1,Vector2.Zero);if(seed<0)return Array.Empty<Vector2>();var visited=new HashSet<int>{seed};var queue=new Queue<int>();queue.Enqueue(seed);var path=new List<Vector2>();while(queue.Count>0){int current=queue.Dequeue();path.Add(field.refine(current));foreach(int next in field.neighbors(current,threshold))if(visited.Add(next))queue.Enqueue(next);}return path.ToArray();
    }
    public void paint_band(Image mask,Vector2[] path,double width,Rect2I domain,Color tint,bool connect)
    {
        double radius=Math.Max(.5,width*.5),spacing=Math.Max(.5,width*.2);var stamps=new List<Vector2>();if(connect&&path.Length>0){stamps.Add(path[0]);double remaining=spacing;for(int index=1;index<path.Length;index++){var a=path[index-1];var b=path[index];double length=a.DistanceTo(b),offset=remaining;while(offset<=length){stamps.Add(a.Lerp(b,(float)(offset/Math.Max(.00001,length))));offset+=spacing;}remaining=offset-length;}if(stamps[^1].DistanceTo(path[^1])>.01)stamps.Add(path[^1]);}else stamps.AddRange(path);foreach(var point in stamps)for(int y=Math.Max(domain.Position.Y,Mathf.FloorToInt(point.Y-radius));y<Math.Min(domain.End.Y,Mathf.CeilToInt(point.Y+radius));y++){double dy=y+.5-point.Y;if(Math.Abs(dy)>radius)continue;double span=Math.Sqrt(Math.Max(0,radius*radius-dy*dy));int left=Math.Max(domain.Position.X,Mathf.CeilToInt(point.X-span-.5)),right=Math.Min(domain.End.X,Mathf.CeilToInt(point.X+span-.5));if(right>left)mask.FillRect(new Rect2I(left,y,right-left,1),tint);}
    }
}
