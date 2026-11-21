using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldConnectionOperations
{
    public Settings augment(Resource source,Settings nodes,GArray roads,Settings cancellation)=>Augment(source,nodes,roads,Cancellation(cancellation));
    internal Settings Augment(Resource source,Settings nodes,GArray roads,Func<bool> cancelled)
    {
        var connections=new GArray();var warnings=new List<string>();Settings Result()=>new() {["connections"]=connections,["warnings"]=warnings.ToArray()};if(!source.Get("connect_settlements").AsBool())return Result();var settlements=new List<Settings>();var gates=new Dictionary<string,List<string>>();var groups=new Settings();
        foreach(var value in source.Get("settlements").AsGodotArray())
        {
            var settlement=value.AsGodotDictionary();if(!Get(settlement,"enabled",true).AsBool())continue;string id=settlement["id"].AsString();var candidates=new HashSet<string>();var ordered=new List<string>();foreach(var roadValue in roads){var road=roadValue.AsGodotDictionary();if(Get(road,"settlement","").AsString()!=id||!Get(road,"enabled",true).AsBool())continue;foreach(string key in new[]{"from","to"}){string end=road[key].AsString();if(candidates.Add(end))ordered.Add(end);}}if(ordered.Count==0)continue;settlements.Add(settlement);gates[id]=ordered;groups[id]=id;
        }
        if(settlements.Count<2)return Result();foreach(var value in source.Get("roads").AsGodotArray()){var road=value.AsGodotDictionary();if(!Get(road,"enabled",true).AsBool())continue;string a=Get(road,"connection_from","").AsString(),b=Get(road,"connection_to","").AsString();if(groups.ContainsKey(a)&&groups.ContainsKey(b))union(groups,a,b);}
        var pairs=new List<Settings>();for(int a=0;a<settlements.Count;a++)for(int b=a+1;b<settlements.Count;b++)
        {
            string from=settlements[a]["id"].AsString(),to=settlements[b]["id"].AsString();bool order=string.CompareOrdinal(from,to)<0;string id="connection:"+(order?from:to)+":"+(order?to:from);double best=double.PositiveInfinity;var ends=new GArray();foreach(string first in gates[from])foreach(string last in gates[to]){double distance=nodes[first].AsVector3().DistanceSquaredTo(nodes[last].AsVector3());if(distance<best){best=distance;ends=new GArray {first,last};}}
            pairs.Add(new Settings {["id"]=id,["from"]=from,["to"]=to,["ends"]=ends,["distance"]=best,["name"]=Get(settlements[a],"name","Settlement").AsString()+" ↔ "+Get(settlements[b],"name","Settlement").AsString()});
        }
        pairs.Sort((a,b)=>!Mathf.IsEqualApprox(a["distance"].AsDouble(),b["distance"].AsDouble())?a["distance"].AsDouble().CompareTo(b["distance"].AsDouble()):string.CompareOrdinal(a["id"].AsString(),b["id"].AsString()));var section=new RoadSectionOperations();var profile=section.defaults(source.Get("connection_road_type").AsString());var restricted=new List<Vector2[]>();var areas=source.Get("exclusions").AsGodotArray().Duplicate();areas.AddRange(source.Get("occupied").AsGodotArray());foreach(var value in areas){var area=value.AsGodotDictionary();if(!Get(area,"protected",true).AsBool())continue;foreach(var polygon in Geometry2D.OffsetPolygon(area["polygon"].AsVector2Array(),(float)(section.outer_half(profile)+1)))restricted.Add(polygon);}
        var field=source.Get("terrain_field").As<RefCounted>();var routing=new RoadRoutingOperations();var dimensions=source.Get("dimensions").AsVector2();
        foreach(var pair in pairs)
        {
            if(cancelled())return new Settings {["cancelled"]=true};string from=pair["from"].AsString(),to=pair["to"].AsString();var overrides=source.Get("connection_overrides").AsGodotDictionary();if(root(groups,from)==root(groups,to)||Get(Get(overrides,pair["id"].AsString(),new Settings()).AsGodotDictionary(),"disabled",false).AsBool())continue;var ends=pair["ends"].AsGodotArray();var first=nodes[ends[0]].AsVector3();var last=nodes[ends[1]].AsVector3();var routed=field==null?new Settings {["points"]=new[]{first,last},["error"]=""}:routing.Route(first,last,new Rect2(-dimensions*.5f,dimensions),point=>Surface(field,point),restricted.ToArray(),49,cancelled,source.Get("connection_bridges").AsBool());
            if(Get(routed,"cancelled",false).AsBool())return new Settings {["cancelled"]=true};string error=routed["error"].AsString();if(error.Length>0){warnings.Add(pair["name"].AsString()+": "+error);continue;}var parts=Parts(source,pair,routed["points"].AsVector3Array(),profile,cancelled);if(Get(parts,"cancelled",false).AsBool())return new Settings {["cancelled"]=true};error=parts["error"].AsString();if(error.Length>0){warnings.Add(pair["name"].AsString()+": "+error);continue;}
            foreach(var roadValue in parts["roads"].AsGodotArray()){var road=roadValue.AsGodotDictionary();var points=road["points"].AsVector3Array();nodes[road["from"]]=points[0];nodes[road["to"]]=points[^1];roads.Add(road);}union(groups,from,to);connections.Add(new Settings {["id"]=pair["id"],["name"]=pair["name"],["from"]=pair["from"],["to"]=pair["to"],["roads"]=parts["roads"],["length"]=parts["length"],["bridges"]=parts["bridges"]});
        }
        var islands=new HashSet<string>();foreach(var id in groups.Keys)islands.Add(root(groups,id.AsString()));if(islands.Count>1)warnings.Add("Some settlements could not be connected without crossing protected terrain, water or excessive grades.");return Result();
    }
}
