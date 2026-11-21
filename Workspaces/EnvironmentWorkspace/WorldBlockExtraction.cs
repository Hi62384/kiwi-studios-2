using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldBlockOperations
{
    public GArray cycle_edges(Settings graph)
    {
        var edges=new Dictionary<string,Settings>();var adjacent=new Dictionary<string,List<string>>();var degree=new Dictionary<string,int>();var queue=new List<string>();
        foreach(var value in graph["edges"].AsGodotArray()){var edge=value.AsGodotDictionary();if(Get(edge,"mode","Ground").AsString()!="Ground")continue;string id=edge["id"].AsString();edges[id]=edge;foreach(string node in new[]{edge["from"].AsString(),edge["to"].AsString()}){if(!adjacent.TryGetValue(node,out var list)){list=new List<string>();adjacent[node]=list;}list.Add(id);degree[node]=degree.GetValueOrDefault(node)+1;}}
        foreach(var pair in degree)if(pair.Value<2)queue.Add(pair.Key);for(int at=0;at<queue.Count;at++){string node=queue[at];foreach(string id in adjacent[node]){if(!edges.Remove(id,out var edge))continue;string other=edge["from"].AsString()==node?edge["to"].AsString():edge["from"].AsString();degree[other]--;if(degree[other]==1)queue.Add(other);}}
        var result=new GArray();foreach(var edge in edges.Values)result.Add(edge);return result;
    }
    public Settings extract(Settings graph,Settings cancellation)=>Extract(graph,Cancellation(cancellation));
    internal Settings Extract(Settings graph,Func<bool> cancelled)
    {
        var half=new Dictionary<string,Settings>();var outgoing=new Dictionary<string,List<string>>();var warnings=new List<string>();var blocks=new Godot.Collections.Array<Settings>();var section=new RoadSectionOperations();
        foreach(var value in cycle_edges(graph))
        {
            var edge=value.AsGodotDictionary();for(int reverse=0;reverse<2;reverse++){var points=edge["points"].AsVector3Array();if(reverse!=0)Array.Reverse(points);string from=edge[reverse!=0?"to":"from"].AsString(),to=edge[reverse!=0?"from":"to"].AsString(),id=edge["id"].AsString()+":"+reverse;var delta=new Vector2(points[1].X-points[0].X,points[1].Z-points[0].Z);half[id]=new Settings {["id"]=id,["twin"]=edge["id"].AsString()+":"+(1-reverse),["from"]=from,["to"]=to,["points"]=points,["angle"]=delta.Angle(),["source"]=Get(edge,"source_road_id",edge["id"]).AsString(),["family"]=Get(edge,"source_family",Get(edge,"source_road_id",edge["id"])).AsString(),["clearance"]=section.outer_half(edge)};if(!outgoing.TryGetValue(from,out var list)){list=new List<string>();outgoing[from]=list;}list.Add(id);}
        }
        foreach(var choices in outgoing.Values)choices.Sort((a,b)=>half[a]["angle"].AsDouble().CompareTo(half[b]["angle"].AsDouble()));var visited=new HashSet<string>();var usedIds=new Dictionary<string,int>();var keys=half.Keys.ToList();keys.Sort(StringComparer.Ordinal);
        foreach(string start in keys)
        {
            if(cancelled())return new Settings {["cancelled"]=true};if(visited.Contains(start))continue;string current=start;var polygon=new List<Vector2>();var sequence=new List<string>();var boundary=new Godot.Collections.Array<Settings>();double clearance=0;bool closed=false;
            for(int step=0;step<=half.Count;step++){if(!visited.Add(current)){closed=current==start;break;}var edge=half[current];var points=edge["points"].AsVector3Array();boundary.Add(edge);clearance=Math.Max(clearance,edge["clearance"].AsDouble());string family=edge["family"].AsString();if(sequence.Count==0||sequence[^1]!=family)sequence.Add(family);for(int index=0;index<points.Length-1;index++)polygon.Add(new Vector2(points[index].X,points[index].Z));if(!outgoing.TryGetValue(edge["to"].AsString(),out var choices))break;int twin=choices.IndexOf(edge["twin"].AsString());if(twin<0)break;current=choices[(twin-1+choices.Count)%choices.Count];}
            if(!closed||polygon.Count<3||area(polygon.ToArray())<=1)continue;var simplified=simplify(polygon.ToArray());if(simplified.Length>4096||Geometry2D.TriangulatePolygon(simplified).Length==0){warnings.Add("A road block is too complex or self-crossing. Simplify its boundary before generating plots.");continue;}if(sequence.Count>1&&sequence[0]==sequence[^1])sequence.RemoveAt(sequence.Count-1);string canonical="";
            for(int offset=0;offset<sequence.Count;offset++){var rotated=new string[sequence.Count];for(int index=0;index<sequence.Count;index++)rotated[index]=sequence[(index+offset)%sequence.Count];string candidate=string.Join("|",rotated);if(canonical.Length==0||string.CompareOrdinal(candidate,canonical)<0)canonical=candidate;}
            string id="block:"+unchecked((uint)GD.Hash(canonical));int count=usedIds.GetValueOrDefault(id);usedIds[id]=count+1;if(count>0)id+=":"+count;blocks.Add(new Settings {["id"]=id,["polygon"]=simplified,["clearance"]=clearance,["boundary"]=boundary});
        }
        return new Settings {["blocks"]=blocks,["warnings"]=warnings.ToArray()};
    }
}
