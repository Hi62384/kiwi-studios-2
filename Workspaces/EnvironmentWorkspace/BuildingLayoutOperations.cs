using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingLayoutOperations : RefCounted
{
    private readonly BuildingSourceOperations _source=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public bool rectangle(Vector2[] polygon,Rect2 bounds)
    {foreach(var point in polygon)if(!((Mathf.IsEqualApprox(point.X,bounds.Position.X)||Mathf.IsEqualApprox(point.X,bounds.End.X))&&(Mathf.IsEqualApprox(point.Y,bounds.Position.Y)||Mathf.IsEqualApprox(point.Y,bounds.End.Y))))return false;return true;}
    public Vector2[] polygon(Rect2 rect)=>new[]{rect.Position,new Vector2(rect.End.X,rect.Position.Y),rect.End,new Vector2(rect.Position.X,rect.End.Y)};
    public Vector2[] stair_endpoints(Settings stair)
    {
        float width=(float)Math.Max(.3,Get(stair,"width",1.0).AsDouble()),length=(float)Math.Max(.5,Get(stair,"length",4.0).AsDouble());int kind=Get(stair,"type",0).AsInt32();var start=new Vector2(0,-.08f);var end=new Vector2(0,length+.08f);
        if(kind==1)end=new Vector2(length*.5f+width*.5f+.08f,length*.5f+width*.5f);else if(kind==2)end=new Vector2(width*2,-.08f);else if(kind==3){start=new Vector2(width*.75f,-.08f);float angle=(float)(Math.Tau*Math.Max(.5,Get(stair,"turns",1.0).AsDouble()));end=new Vector2(Mathf.Cos(angle),Mathf.Sin(angle))*width*.75f+new Vector2(-Mathf.Sin(angle),Mathf.Cos(angle))*.08f;}
        var position=Get(stair,"position",Vector2.Zero).AsVector2();float rotation=-Mathf.DegToRad((float)Get(stair,"yaw",0.0).AsDouble());return new[]{start.Rotated(rotation)+position,end.Rotated(rotation)+position};
    }
    public string region(Settings floor,Vector2 point,Resource source)
    {
        foreach(var value in Get(floor,"rooms",new GArray()).AsGodotArray())
        {var room=value.AsGodotDictionary();if(!Geometry2D.IsPointInPolygon(point,Get(room,"polygon",Array.Empty<Vector2>()).AsVector2Array()))continue;bool inHole=false;foreach(var hole in Get(room,"holes",new GArray()).AsGodotArray())inHole|=Geometry2D.IsPointInPolygon(point,hole.AsVector2Array());if(!inHole)return floor["id"].AsString()+":"+room["id"].AsString();}
        return !Geometry2D.IsPointInPolygon(point,Get(floor,"footprint",source.Get("footprint")).AsVector2Array())?"outside":"";
    }
    public Settings connectivity(Resource source)
    {
        var regions=new Settings {["outside"]=new Settings {["name"]="Exterior",["floor"]=""}};var edges=new GArray();var warnings=new List<string>();var floors=source.Get("floors").AsGodotArray();
        foreach(var floorValue in floors)
        {
            var floor=floorValue.AsGodotDictionary();string floorId=floor["id"].AsString();foreach(var roomValue in Get(floor,"rooms",new GArray()).AsGodotArray()){var room=roomValue.AsGodotDictionary();regions[floorId+":"+room["id"].AsString()]=new Settings {["name"]=Get(room,"name","Room"),["floor"]=floorId,["polygon"]=Get(room,"polygon",Array.Empty<Vector2>()),["holes"]=Get(room,"holes",new GArray())};}
            foreach(var wallValue in Get(floor,"walls",new GArray()).AsGodotArray())
            {
                var wall=wallValue.AsGodotDictionary();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();var direction=(b-a).Normalized();var offset=new Vector2(-direction.Y,direction.X)*((float)source.Get("wall_thickness").AsDouble()*.5f+.05f);
                foreach(var openingValue in Get(wall,"openings",new GArray()).AsGodotArray())
                {
                    var opening=openingValue.AsGodotDictionary();if(Get(opening,"type", "").AsString() is not ("door" or "slider" or "arch")||Get(opening,"bottom",0.0).AsDouble()>.15)continue;var point=a.Lerp(b,(float)Get(opening,"t",.5).AsDouble());string one=region(floor,point+offset,source),two=region(floor,point-offset,source),id=opening["id"].AsString();if(one.Length==0||two.Length==0||one==two){warnings.Add("Opening "+id+" does not connect two usable regions.");continue;}if(Get(opening,"width",1.0).AsDouble()<.65||Get(opening,"height",2.0).AsDouble()<1.8){warnings.Add("Opening "+id+" is too small for ordinary pedestrian clearance.");continue;}edges.Add(new Settings {["from"]=one,["to"]=two,["kind"]="door",["opening"]=id,["floor"]=floorId,["position"]=new Vector3(point.X,(float)floor["elevation"].AsDouble(),point.Y)});
                }
            }
        }
        foreach(var stairValue in source.Get("stairs").AsGodotArray())
        {
            var stair=stairValue.AsGodotDictionary();string from="",to="";var points=stair_endpoints(stair);double low=0,high=0;foreach(var floorValue in floors){var floor=floorValue.AsGodotDictionary();string id=floor["id"].AsString();if(id==Get(stair,"from", "").AsString()){from=region(floor,points[0],source);low=floor["elevation"].AsDouble();}if(id==Get(stair,"to", "").AsString()){to=region(floor,points[1],source);high=floor["elevation"].AsDouble();}}
            if(from.Length==0||to.Length==0||from=="outside"||to=="outside"||high<=low)warnings.Add("A staircase is disconnected from its level's rooms.");else edges.Add(new Settings {["from"]=from,["to"]=to,["kind"]="stairs",["stair"]=Get(stair,"id", "")});
        }
        var reached=new Settings {["outside"]=true};var queue=new Queue<string>();queue.Enqueue("outside");while(queue.TryDequeue(out var current))foreach(var value in edges){var edge=value.AsGodotDictionary();string from=edge["from"].AsString(),to=edge["to"].AsString(),next=from==current?to:to==current?from:"";if(next.Length>0&&!reached.ContainsKey(next)){reached[next]=true;queue.Enqueue(next);}}
        foreach(var id in regions.Keys)if(!reached.ContainsKey(id))warnings.Add(regions[id].AsGodotDictionary()["name"].AsString()+" has no connected route from outside.");return new Settings {["regions"]=regions,["connections"]=edges,["reachable"]=reached,["warnings"]=warnings.ToArray()};
    }
}
