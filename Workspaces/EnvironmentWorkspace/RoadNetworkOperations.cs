using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RoadNetworkOperations : RefCounted
{
    private readonly RoadGeometryOperations _geometry=new();
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Func<bool> Cancellation(Settings state)
    {if(!Get(state,"enabled",false).AsBool())return()=>false;var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/road_network.gd");return()=>bridge.Call("_cancel_requested",state).AsBool();}
    private static int CompareText(string a,string b)
    {var first=a.EnumerateRunes().GetEnumerator();var last=b.EnumerateRunes().GetEnumerator();while(true){bool x=first.MoveNext(),y=last.MoveNext();if(!x||!y)return x?1:y?-1:0;int compared=first.Current.Value.CompareTo(last.Current.Value);if(compared!=0)return compared;}}
    private sealed class NodeEntry
    {internal string Id="";internal Vector3 Position;}
    private sealed class NodeIndex
    {
        internal readonly Settings Nodes;
        private readonly List<NodeEntry> _ordered=new();
        private readonly Dictionary<string,NodeEntry> _ids=new(StringComparer.Ordinal);
        internal NodeIndex(Settings nodes){Nodes=nodes;foreach(var pair in nodes){var entry=new NodeEntry {Id=pair.Key.AsString(),Position=pair.Value.AsVector3()};_ordered.Add(entry);_ids[entry.Id]=entry;}}
        internal string Find(Vector3 position,string prefix)
        {foreach(var entry in _ordered)if(entry.Position.DistanceTo(position)<.001)return entry.Id;string id=prefix+Variant.From(position.Snapped(Vector3.One*.001f)).ToString();Nodes[id]=position;if(_ids.TryGetValue(id,out var old))old.Position=position;else{var entry=new NodeEntry {Id=id,Position=position};_ids[id]=entry;_ordered.Add(entry);}return id;}
    }
    public string node(Settings nodes,Vector3 position,string prefix)=>new NodeIndex(nodes).Find(position,prefix);
    public Settings canonical(Settings input)
    {
        var result=new Settings();var aliases=new Settings();var cells=new Dictionary<Vector3I,List<string>>();var keys=input.Keys.ToList();keys.Sort((a,b)=>CompareText(a.ToString(),b.ToString()));foreach(var key in keys)
        {
            var point=input[key].AsVector3();var cell=(Vector3I)(point/.001f).Floor();string found="";for(int z=-1;z<=1;z++)for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)if(cells.TryGetValue(cell+new Vector3I(x,y,z),out var candidates))foreach(string candidate in candidates)if(result[candidate].AsVector3().DistanceTo(point)<.001&&(found.Length==0||CompareText(candidate,found)<0))found=candidate;
            if(found.Length==0){found=key.ToString();result[found]=point;if(!cells.TryGetValue(cell,out var list)){list=new List<string>();cells[cell]=list;}list.Add(found);}aliases[key]=found;
        }
        return new Settings {["nodes"]=result,["aliases"]=aliases};
    }
    private sealed record CandidateResult(List<Vector4I> Pairs,string Error,bool Cancelled);
    private static CandidateResult Candidates(IReadOnlyList<Vector3[]> paths,Func<bool> cancelled)
    {
        var buckets=new Dictionary<Vector2I,List<Vector2I>>();var pairs=new HashSet<Vector4I>();var order=new List<Vector4I>();int count=0;for(int path=0;path<paths.Count;path++)
        {
            var points=paths[path];count+=points.Length;if(count>65536)return new(order,"Road sampling exceeds 65,536 points. Generate smaller regions or simplify road paths.",false);for(int segment=0;segment<points.Length-1;segment++){if(cancelled())return new(order,"",true);var a=new Vector2(points[segment].X,points[segment].Z);var b=new Vector2(points[segment+1].X,points[segment+1].Z);var low=(Vector2I)(a.Min(b)/16).Floor();var high=(Vector2I)(a.Max(b)/16).Floor();var current=new Vector2I(path,segment);for(int z=low.Y;z<=high.Y;z++)for(int x=low.X;x<=high.X;x++){var cell=new Vector2I(x,z);if(!buckets.TryGetValue(cell,out var candidates)){candidates=new List<Vector2I>();buckets[cell]=candidates;}foreach(var other in candidates){if(other.X==path)continue;var pair=new Vector4I(other.X,other.Y,path,segment);if(pairs.Add(pair)){order.Add(pair);if(order.Count>500000)return new(order,"This road region exceeds its intersection budget. Split dense networks into smaller regions.",false);}}candidates.Add(current);}}
        }
        return new(order,"",false);
    }
    public Settings candidates(GArray paths,Settings cancellation)
    {var result=Candidates(paths.Select(value=>value.AsGodotDictionary()["points"].AsVector3Array()).ToArray(),Cancellation(cancellation));if(result.Cancelled)return new Settings {["cancelled"]=true};if(result.Error.Length>0)return new Settings {["error"]=result.Error};var pairs=new GArray();foreach(var pair in result.Pairs)pairs.Add(pair);return new Settings {["pairs"]=pairs};}
    private sealed record Marker(int Segment,double T,string Node);
    private sealed record Path(Settings Source,Vector3[] Points,List<Marker> Markers);
    public Settings graph(Resource source,Settings cancellation,Settings settlementLayout)=>Graph(source,Cancellation(cancellation),settlementLayout);
    internal Settings Graph(Resource source,Func<bool> cancelled,Settings settlementLayout)
    {
        var input=source.Get("nodes").AsGodotDictionary().Duplicate();input.Merge(Get(settlementLayout,"nodes",new Settings()).AsGodotDictionary(),true);var canonicalNodes=canonical(input);var nodes=canonicalNodes["nodes"].AsGodotDictionary();var aliases=canonicalNodes["aliases"].AsGodotDictionary();var index=new NodeIndex(nodes);var edges=new Godot.Collections.Array<Settings>();var warnings=new List<string>();var paths=new List<Path>();var roads=source.Get("roads").AsGodotArray().ToList();roads.AddRange(Get(settlementLayout,"roads",new GArray()).AsGodotArray());var field=source.Get("terrain_field").As<RefCounted>();
        foreach(var value in roads)
        {
            var road=value.AsGodotDictionary().Duplicate(true);road["from"]=Get(aliases,road["from"],road["from"]);road["to"]=Get(aliases,road["to"],road["to"]);if(!Get(road,"enabled",true).AsBool())continue;var points=_geometry.sample(road["points"].AsVector3Array(),2);points[0]=nodes[road["from"]].AsVector3();points[^1]=nodes[road["to"]].AsVector3();
            if(Get(road,"mode","Ground").AsString()=="Ground"&&Get(road,"follow_terrain",false).AsBool()&&field!=null){bool warned=false;for(int point=1;point<points.Length-1;point++){var coordinate=new Vector2(points[point].X,points[point].Z);var surface=field is WorldTerrainField terrain?terrain.sample(coordinate):field.Call("sample",coordinate).AsGodotDictionary();if(surface.Count==0)continue;points[point].Y=(float)(surface["height"].AsDouble()+.03);if(Get(surface,"water",false).AsBool()&&!warned){warnings.Add(Get(road,"name","Road").AsString()+" crosses water. Use bridge mode or route around it.");warned=true;}}}
            var markers=new List<Marker>{new(0,0,road["from"].AsString()),new(points.Length-2,1,road["to"].AsString())};paths.Add(new Path(road,points,markers));foreach(var regionValue in source.Get("regions").AsGodotArray()){var bounds=regionValue.AsGodotDictionary()["bounds"].AsRect2();var corners=new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)};for(int segment=0;segment<points.Length-1;segment++){var a=new Vector2(points[segment].X,points[segment].Z);var b=new Vector2(points[segment+1].X,points[segment+1].Z);for(int border=0;border<4;border++){var cross=Geometry2D.SegmentIntersectsSegment(a,b,corners[border],corners[(border+1)%4]);if(cross.VariantType!=Variant.Type.Vector2)continue;double t=a.DistanceTo(cross.AsVector2())/Math.Max(.0001,a.DistanceTo(b));var position=points[segment].Lerp(points[segment+1],(float)t);markers.Add(new Marker(segment,t,index.Find(position,"border:")));}}}
        }
        var candidates=Candidates(paths.Select(path=>path.Points).ToArray(),cancelled);if(candidates.Cancelled)return new Settings {["cancelled"]=true};if(candidates.Error.Length>0)return new Settings {["errors"]=new[]{candidates.Error}};
        foreach(var pair in candidates.Pairs)
        {
            if(cancelled())return new Settings {["cancelled"]=true};int left=pair.X,right=pair.Z,i=pair.Y,j=pair.W;var a=paths[left].Points;var b=paths[right].Points;var first=new Vector2(a[i].X,a[i].Z);var firstEnd=new Vector2(a[i+1].X,a[i+1].Z);var last=new Vector2(b[j].X,b[j].Z);var lastEnd=new Vector2(b[j+1].X,b[j+1].Z);var cross=Geometry2D.SegmentIntersectsSegment(first,firstEnd,last,lastEnd);if(cross.VariantType!=Variant.Type.Vector2)continue;var point=cross.AsVector2();double t=first.DistanceTo(point)/Math.Max(.0001,first.DistanceTo(firstEnd)),u=last.DistanceTo(point)/Math.Max(.0001,last.DistanceTo(lastEnd)),ay=Mathf.Lerp((double)a[i].Y,a[i+1].Y,t),by=Mathf.Lerp((double)b[j].Y,b[j+1].Y,u);if(Math.Abs(ay-by)>1)continue;string id=index.Find(new Vector3(point.X,(float)((ay+by)*.5),point.Y),"junction:");paths[left].Markers.Add(new Marker(i,t,id));paths[right].Markers.Add(new Marker(j,u,id));
        }
        foreach(var entry in paths)
        {
            entry.Markers.Sort((a,b)=>(a.Segment+a.T).CompareTo(b.Segment+b.T));var unique=new List<Marker>();foreach(var marker in entry.Markers)if(unique.Count==0||unique[^1].Node!=marker.Node)unique.Add(marker);for(int cut=0;cut<unique.Count-1;cut++){var first=unique[cut];var last=unique[cut+1];if(first.Node==last.Node)continue;var points=new List<Vector3>{nodes[first.Node].AsVector3()};var path=entry.Points;for(int point=first.Segment+1;point<=last.Segment;point++)if(new Vector2(points[^1].X,points[^1].Z).DistanceTo(new Vector2(path[point].X,path[point].Z))>.001)points.Add(path[point]);var end=nodes[last.Node].AsVector3();if(new Vector2(points[^1].X,points[^1].Z).DistanceTo(new Vector2(end.X,end.Z))>.001)points.Add(end);else if(points.Count>1)points[^1]=end;if(points.Count<2)continue;var edge=entry.Source.Duplicate(true);edge["source_road_id"]=edge["id"];edge["source_from"]=edge["from"];edge["source_to"]=edge["to"];edge["id"]=edge["id"].AsString()+":"+first.Node+":"+last.Node;edge["from"]=first.Node;edge["to"]=last.Node;edge["points"]=points.ToArray();double distance=0;for(int segment=0;segment<first.Segment;segment++)distance+=path[segment].DistanceTo(path[segment+1]);distance+=path[first.Segment].DistanceTo(nodes[first.Node].AsVector3());edge["distance_start"]=distance;edges.Add(edge);}
        }
        var adjacency=new Settings();foreach(var edge in edges)foreach(var id in new[]{edge["from"],edge["to"]}){if(!adjacency.ContainsKey(id))adjacency[id]=new GArray();adjacency[id].AsGodotArray().Add(edge["id"]);}return new Settings {["nodes"]=nodes,["edges"]=edges,["adjacency"]=adjacency,["warnings"]=warnings.ToArray(),["node_aliases"]=aliases};
    }
}
