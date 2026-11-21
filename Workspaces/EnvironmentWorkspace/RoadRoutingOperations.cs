using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RoadRoutingOperations : RefCounted
{
    public double cost(AStar3D graph,long from,long to,double slopeWeight)
    {var a=graph.GetPointPosition(from);var b=graph.GetPointPosition(to);double horizontal=new Vector2(a.X,a.Z).DistanceTo(new Vector2(b.X,b.Z));return horizontal*(1+Math.Pow(Math.Abs(a.Y-b.Y)/Math.Max(.01,horizontal),2)*slopeWeight);}
    public double estimate(AStar3D graph,long from,long to)
    {var a=graph.GetPointPosition(from);var b=graph.GetPointPosition(to);return new Vector2(a.X,a.Z).DistanceTo(new Vector2(b.X,b.Z));}
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings Failure(string text,bool cancelled=false){var result=new Settings {["points"]=Array.Empty<Vector3>(),["error"]=text};if(cancelled)result["cancelled"]=true;return result;}
    private static Vector2 Flat(Vector3 point)=>new(point.X,point.Z);
    private static Func<bool> Cancellation(Settings state)
    {if(!Get(state,"enabled",false).AsBool())return()=>false;var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd");return()=>bridge.Call("_cancel_requested",state).AsBool();}
    private static Func<Vector2,Settings> Surface(Settings state)
    {if(state.TryGetValue("field",out var value)){var sampler=value.As<RefCounted>();if(sampler is WorldTerrainField field)return field.sample;return point=>sampler.Call("sample",point).AsGodotDictionary();}var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd");return point=>bridge.Call("_surface_sample",state,point).AsGodotDictionary();}
    private static bool Intersects(Vector2 a,Vector2 b,Vector2[] polygon)
    {for(int edge=0;edge<polygon.Length;edge++)if(Geometry2D.SegmentIntersectsSegment(a,b,polygon[edge],polygon[(edge+1)%polygon.Length]).VariantType!=Variant.Type.Nil)return true;return false;}
    public Settings route(Vector3 start,Vector3 end,Rect2 bounds,Settings state,GArray restricted,int resolution,bool allowWater)=>Route(start,end,bounds,Surface(state),restricted.Select(value=>value.AsVector2Array()).ToArray(),resolution,Cancellation(state),allowWater);
    internal Settings Route(Vector3 start,Vector3 end,Rect2 bounds,Func<Vector2,Settings> surface,Vector2[][] restricted,int resolution,Func<bool> cancelled,bool allowWater)
    {
        if(!bounds.Position.IsFinite()||!bounds.Size.IsFinite()||bounds.Size.X<=0||bounds.Size.Y<=0)return Failure("Choose a positive, finite routing region.");foreach(var point in new[]{start,end}){var sample=surface(Flat(point));if(sample.Count==0||Get(sample,"water",false).AsBool()&&!allowWater)return Failure("Road endpoints must be on accessible dry ground, or bridges must be enabled.");}
        using var graph=new RoadCostGraph();int count=Math.Clamp(resolution,9,97);var enabled=new GArray();var known=new HashSet<long>();var step=bounds.Size/(count-1);for(int z=0;z<count;z++)
        {
            if(cancelled())return Failure("Generation canceled.",true);for(int x=0;x<count;x++){var p=bounds.Position+new Vector2(x,z)*step;if(restricted.Any(polygon=>Geometry2D.IsPointInPolygon(p,polygon)))continue;var sample=surface(p);bool wet=Get(sample,"water",false).AsBool();if(sample.Count==0||wet&&!allowWater)continue;double height=sample["height"].AsDouble();if(wet)height=Math.Max(height,Get(sample,"water_level",height).AsDouble()+.7);long id=x+z*count;graph.AddPoint(id,new Vector3(p.X,(float)height,p.Y),wet?5:1);enabled.Add(id);known.Add(id);}
        }
        foreach(var value in enabled)
        {
            if(cancelled())return Failure("Generation canceled.",true);long id=value.AsInt64();int x=(int)(id%count),z=(int)(id/count);foreach(var offset in new[]{new Vector2I(1,0),new Vector2I(0,1),new Vector2I(1,1),new Vector2I(-1,1)})
            {
                var next=new Vector2I(x,z)+offset;long target=next.X+next.Y*count;if(next.X<0||next.Y<0||next.X>=count||next.Y>=count||!known.Contains(target))continue;if(offset.X!=0&&offset.Y!=0&&(!known.Contains(next.X+z*count)||!known.Contains(x+next.Y*count)))continue;var first=graph.GetPointPosition(id);var last=graph.GetPointPosition(target);if(restricted.Any(polygon=>Intersects(Flat(first),Flat(last),polygon)))continue;bool blocked=false;if(!allowWater)foreach(float portion in new[]{.25f,.5f,.75f}){var sample=surface(Flat(first.Lerp(last,portion)));if(sample.Count==0||Get(sample,"water",false).AsBool()){blocked=true;break;}}if(!blocked)graph.ConnectPoints(id,target);
            }
        }
        long a=Reachable(graph,enabled,start,surface,restricted,allowWater,cancelled),b=Reachable(graph,enabled,end,surface,restricted,allowWater,cancelled);if(a<0||b<0)return Failure("No dry, unrestricted route is available.");var points=new List<Vector3>(graph.GetPointPath(a,b));if(points.Count==0)return Failure("The road endpoints are disconnected by water or protected land.");if(a==b&&Legal(start,end,surface,restricted,allowWater,cancelled))return new Settings {["points"]=new[]{start,end},["error"]=""};if(!points[0].IsEqualApprox(start))points.Insert(0,start);if(!points[^1].IsEqualApprox(end))points.Add(end);var result=new List<Vector3>{points[0]};for(int index=1;index<points.Count-1;index++){var before=(points[index]-points[index-1]).Normalized();var after=(points[index+1]-points[index]).Normalized();if(before.Dot(after)<.9995)result.Add(points[index]);}result.Add(points[^1]);return new Settings {["points"]=result.ToArray(),["error"]=""};
    }
    private static long Reachable(AStar3D graph,GArray enabled,Vector3 point,Func<Vector2,Settings> surface,Vector2[][] restricted,bool allowWater,Func<bool> cancelled)
    {var candidates=enabled.Select(value=>value.AsInt64()).ToList();candidates.Sort((a,b)=>graph.GetPointPosition(a).DistanceSquaredTo(point).CompareTo(graph.GetPointPosition(b).DistanceSquaredTo(point)));for(int index=0;index<Math.Min(16,candidates.Count);index++){long id=candidates[index];if(Legal(point,graph.GetPointPosition(id),surface,restricted,allowWater,cancelled))return id;}return -1;}
    public long reachable(AStar3D graph,Settings enabled,Vector3 point,Settings state,GArray restricted,bool allowWater)=>Reachable(graph,new GArray(enabled.Keys),point,Surface(state),restricted.Select(value=>value.AsVector2Array()).ToArray(),allowWater,Cancellation(state));
    private static bool Legal(Vector3 a,Vector3 b,Func<Vector2,Settings> surface,Vector2[][] restricted,bool allowWater,Func<bool> cancelled)
    {for(int index=0;index<restricted.Length;index++){if(index%64==0&&cancelled())return false;var polygon=restricted[index];if(Geometry2D.IsPointInPolygon(Flat(a),polygon)||Geometry2D.IsPointInPolygon(Flat(b),polygon)||Intersects(Flat(a),Flat(b),polygon))return false;}if(!allowWater)foreach(float portion in new[]{.25f,.5f,.75f}){var sample=surface(Flat(a.Lerp(b,portion)));if(sample.Count==0||Get(sample,"water",false).AsBool())return false;}return true;}
    public bool legal(Vector3 a,Vector3 b,Settings state,GArray restricted,bool allowWater)=>Legal(a,b,Surface(state),restricted.Select(value=>value.AsVector2Array()).ToArray(),allowWater,Cancellation(state));
}
