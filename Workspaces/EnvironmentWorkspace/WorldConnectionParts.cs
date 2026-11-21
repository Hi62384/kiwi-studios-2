using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldConnectionOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Func<bool> Cancellation(Settings state)
    {if(!Get(state,"enabled",false).AsBool())return()=>false;var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_connections.gd");return()=>bridge.Call("_cancel_requested",state).AsBool();}
    private static Settings Surface(RefCounted field,Vector2 point)=>field is WorldTerrainField native?native.sample(point):field.Call("sample",point).AsGodotDictionary();
    public Settings parts(Resource source,Settings pair,Vector3[] path,Settings profile,Settings cancellation)=>Parts(source,pair,path,profile,Cancellation(cancellation));
    internal Settings Parts(Resource source,Settings pair,Vector3[] path,Settings profile,Func<bool> cancelled)
    {
        var points=new List<Vector3>();for(int index=0;index<path.Length-1;index++){int count=Math.Max(1,(int)Math.Ceiling(path[index].DistanceTo(path[index+1])/2.0));if(points.Count+count>32768)return new Settings {["error"]="Connection sampling exceeds its region budget."};for(int step=0;step<count;step++)points.Add(path[index].Lerp(path[index+1],(float)step/count));}points.Add(path[^1]);
        var ground=new float[points.Count];var wet=new bool[points.Count];var target=new float[points.Count];var arc=new float[points.Count];var field=source.Get("terrain_field").As<RefCounted>();
        for(int index=0;index<points.Count;index++)
        {if(cancelled())return new Settings {["cancelled"]=true};var point=points[index];var surface=field==null?new Settings {["height"]=point.Y}:Surface(field,new Vector2(point.X,point.Z));if(surface.Count==0)return new Settings {["error"]="Connection leaves its terrain."};double height=surface["height"].AsDouble()+.03;ground[index]=(float)height;wet[index]=Get(surface,"water",false).AsBool();target[index]=(float)(wet[index]?Math.Max(height,Get(surface,"water_level",height).AsDouble()+.7):height);if(index>0)arc[index]=arc[index-1]+new Vector2(point.X,point.Z).DistanceTo(new Vector2(points[index-1].X,points[index-1].Z));}
        for(int index=1;index<points.Count;index++)target[index]=(float)Math.Max(target[index],target[index-1]-.15*((double)arc[index]-arc[index-1]));for(int index=points.Count-2;index>=0;index--)target[index]=(float)Math.Max(target[index],target[index+1]-.15*((double)arc[index+1]-arc[index]));
        if(target[0]>ground[0]+.08||target[^1]>ground[^1]+.08)return new Settings {["error"]="Bridge approaches or terrain grades cannot meet the settlement gates. Move a gate or route this connection manually."};var elevated=new bool[points.Count];bool any=false;
        for(int index=0;index<points.Count;index++){elevated[index]=wet[index]||target[index]>ground[index]+.05;any|=elevated[index];var point=points[index];point.Y=target[index];points[index]=point;if(index>0&&Math.Abs((double)target[index]-target[index-1])>Math.Max(.01,(double)arc[index]-arc[index-1])*.3)return new Settings {["error"]="A connection exceeds its safe construction grade."};}
        if(!source.Get("connection_bridges").AsBool()&&any)return new Settings {["error"]="A bridge or major embankment is required. Enable connection bridges or route around this obstacle."};var roads=new Godot.Collections.Array<Settings>();int start=0,bridges=0;bool mode=elevated[0];var ends=pair["ends"].AsGodotArray();string id=pair["id"].AsString();
        for(int index=1;index<points.Count;index++)
        {
            if(elevated[index]==mode&&index<points.Count-1)continue;int first=mode?Math.Max(0,start-1):start;if(index>first){var road=profile.Duplicate(true);road["id"]=id+":"+roads.Count;road["name"]=pair["name"];road["from"]=first==0?ends[0]:Variant.From(id+":point:"+first);road["to"]=index==points.Count-1?ends[1]:Variant.From(id+":point:"+index);road["points"]=points.GetRange(first,index-first+1).ToArray();road["enabled"]=true;road["mode"]=mode?"Bridge":"Ground";road["auto_piers"]=mode;road["connection"]=pair["id"];road["connection_from"]=pair["from"];road["connection_to"]=pair["to"];roads.Add(road);if(mode)bridges++;}start=index;mode=elevated[index];
        }
        for(int index=1;index<roads.Count;index++){var boundary=roads[index]["points"].AsVector3Array()[0];var previous=new List<Vector3>(roads[index-1]["points"].AsVector3Array());while(previous.Count>2&&previous[^2].DistanceTo(boundary)<previous[^1].DistanceTo(boundary))previous.RemoveAt(previous.Count-1);previous[^1]=boundary;roads[index-1]["points"]=previous.ToArray();roads[index-1]["to"]=roads[index]["from"];}
        return new Settings {["roads"]=roads,["bridges"]=bridges,["length"]=arc[^1],["error"]=""};
    }
    public string root(Settings groups,string id){while(groups[id].AsString()!=id)id=groups[id].AsString();return id;}
    public void union(Settings groups,string a,string b)=>groups[root(groups,b)]=root(groups,a);
    public Resource make_editable(Resource source,Settings connection)
    {
        var next=new WorldSourceOperations().copy(source);next.Get("connection_overrides").AsGodotDictionary()[connection["id"]]=new Settings {["disabled"]=true};foreach(var value in connection["roads"].AsGodotArray()){var original=value.AsGodotDictionary();var points=original["points"].AsVector3Array();int start=0,chunk=0;string from=original["from"].AsString();while(start<points.Length-1){int end=Math.Min(points.Length-1,start+511);var road=original.Duplicate(true);string id=original["id"].AsString();road["id"]=id+":editable:"+chunk;road["points"]=points[start..(end+1)];road["from"]=from;road["to"]=end==points.Length-1?original["to"]:Variant.From(id+":cut:"+end);var nodes=next.Get("nodes").AsGodotDictionary();nodes[road["from"]]=points[start];nodes[road["to"]]=points[end];next.Get("roads").AsGodotArray().Add(road);from=road["to"].AsString();start=end;chunk++;}}return next;
    }
}
