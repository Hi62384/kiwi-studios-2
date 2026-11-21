using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingPlanOperations : RefCounted
{
    private readonly BuildingSessionOperations _buildings=new();
    private readonly BuildingSourceOperations _sources=new();
    private readonly BuildingGeometryOperations _geometry=new();
    private readonly ModelDocumentOperations _documents=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Control? Workspace(Control owner)=>owner.Get("workspace").As<Control>();
    private static RefCounted Session(Control owner)=>Workspace(owner)!.Get("session").As<RefCounted>();
    private static string Id(Control owner)=>owner.Get("building_id").AsString();
    private static int Floor(Control owner)=>owner.Get("current_floor").AsInt32();
    public Resource? authored(Control owner)
    {var workspace=Workspace(owner);return GodotObject.IsInstanceValid(workspace)?_buildings.source(_documents.component(workspace!.Get("session").As<RefCounted>().Get("document").As<Resource>(),Id(owner))):null;}
    public Vector2 to_screen(Control owner,Vector2 point)=>owner.Size*.5f+owner.Get("pan").AsVector2()+point*(float)owner.Get("zoom").AsDouble();
    public Vector2 to_plan(Control owner,Vector2 point)=>(point-owner.Size*.5f-owner.Get("pan").AsVector2())/(float)owner.Get("zoom").AsDouble();
    public Vector2 snap_point(Control owner,Vector2 point,bool control)=>owner.Get("snap").AsBool()!=control?point.Snapped(Vector2.One*(float)owner.Get("grid_step").AsDouble()):point;
    public void set_footprint(Resource source,Settings floor,Vector2[] polygon)
    {
        var floors=source.Get("floors").AsGodotArray();string id=floor["id"].AsString();if(id==floors[0].AsGodotDictionary()["id"].AsString()){foreach(var value in floors){var other=value.AsGodotDictionary();if(other["id"].AsString()!=id&&!other.ContainsKey("footprint"))other["footprint"]=source.Get("footprint");}source.Set("footprint",polygon);}floor["footprint"]=polygon;
    }
    public void replace_points(Resource source,Settings floor,Settings replacements)
    {
        foreach(var value in floor["walls"].AsGodotArray()){var wall=value.AsGodotDictionary();if(replacements.TryGetValue(wall["a"],out var a))wall["a"]=a;if(replacements.TryGetValue(wall["b"],out var b))wall["b"]=b;}var footprint=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();for(int index=0;index<footprint.Length;index++)if(replacements.TryGetValue(footprint[index],out var point))footprint[index]=point.AsVector2();set_footprint(source,floor,footprint);foreach(var value in Get(floor,"rooms",new GArray()).AsGodotArray()){var room=value.AsGodotDictionary();var polygon=Get(room,"polygon",Array.Empty<Vector2>()).AsVector2Array();for(int index=0;index<polygon.Length;index++)if(replacements.TryGetValue(polygon[index],out var point))polygon[index]=point.AsVector2();room["polygon"]=polygon;}
    }
    public Settings partition_walls(GArray walls)
    {
        var result=new GArray();var seen=new HashSet<(Vector2,Vector2)>();foreach(var value in walls)
        {
            var wall=value.AsGodotDictionary();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();var delta=b-a;var ts=new List<double>{0,1};foreach(var otherValue in walls){var other=otherValue.AsGodotDictionary();foreach(var point in new[]{other["a"].AsVector2(),other["b"].AsVector2()}){double t=Math.Clamp((point-a).Dot(delta)/Math.Max(.00001,delta.LengthSquared()),0,1);if(point.DistanceTo(a+delta*(float)t)<.0001)ts.Add(t);}}ts.Sort();var unique=new List<double>();foreach(double t in ts)if(unique.Count==0||Math.Abs(unique[^1]-t)>.00001)unique.Add(t);
            for(int index=0;index<unique.Count-1;index++)
            {
                var first=a+delta*(float)unique[index];var last=a+delta*(float)unique[index+1];if(seen.Contains((first,last))||seen.Contains((last,first)))continue;var part=wall.Duplicate(true);part["id"]=index==0?wall["id"]:Variant.From(wall["id"].AsString()+":segment:"+index);part["a"]=first;part["b"]=last;var openings=new GArray();part["openings"]=openings;foreach(var openingValue in Get(wall,"openings",new GArray()).AsGodotArray()){var opening=openingValue.AsGodotDictionary();double center=Get(opening,"t",.5).AsDouble()*delta.Length(),half=Get(opening,"width",1.0).AsDouble()*.5,low=unique[index]*delta.Length(),high=unique[index+1]*delta.Length();if(center<low||center>high)continue;if(center-half<low-.00001||center+half>high+.00001)return new Settings {["walls"]=new GArray(),["error"]="A room boundary crosses an opening. Move the opening first."};var copy=opening.Duplicate(true);copy["t"]=(center-low)/Math.Max(.001,high-low);openings.Add(copy);}seen.Add((first,last));result.Add(part);
            }
        }
        return new Settings {["walls"]=result,["error"]=""};
    }
    private static void Status(Control owner,string message)=>Workspace(owner)!.Get("status").As<Label>().Text=message;
    public bool room(Control owner,Resource source,Settings floor,Rect2 box,string id)
    {
        if(box.Size.X<.2||box.Size.Y<.2)return false;var polygon=new[]{box.Position,new Vector2(box.End.X,box.Position.Y),box.End,new Vector2(box.Position.X,box.End.Y)};var merged=Geometry2D.MergePolygons(Get(floor,"footprint",source.Get("footprint")).AsVector2Array(),polygon);if(merged.Count!=1){Status(owner,"The new room must connect to the building footprint.");return false;}set_footprint(source,floor,merged[0]);var rooms=new GArray();foreach(var value in Get(floor,"rooms",new GArray()).AsGodotArray())
        {
            var room=value.AsGodotDictionary();var contours=Geometry2D.ClipPolygons(Get(room,"polygon",source.Get("footprint")).AsVector2Array(),polygon);for(int part=0;part<contours.Count;part++){if(Geometry2D.IsPolygonClockwise(contours[part]))continue;var retained=room.Duplicate(true);retained["polygon"]=contours[part];if(part>0)retained["id"]=room["id"].AsString()+":part:"+part;var holes=new GArray();retained["holes"]=holes;foreach(var previous in Get(room,"holes",new GArray()).AsGodotArray())foreach(var clipped in Geometry2D.IntersectPolygons(previous.AsVector2Array(),contours[part]))holes.Add(clipped);foreach(var contour in contours)if(Geometry2D.IsPolygonClockwise(contour)&&Geometry2D.IsPointInPolygon(contour[0],contours[part]))holes.Add(contour);rooms.Add(retained);}
        }
        rooms.Add(new Settings {["id"]=id,["name"]="Room "+(rooms.Count+1),["polygon"]=polygon});floor["rooms"]=rooms;for(int index=0;index<4;index++)floor["walls"].AsGodotArray().Add(new Settings {["id"]=id+":"+index,["a"]=polygon[index],["b"]=polygon[(index+1)%4],["height"]=Get(floor,"height",3.0),["openings"]=new GArray()});var result=partition_walls(floor["walls"].AsGodotArray());if(result["error"].AsString().Length>0){Status(owner,result["error"].AsString());return false;}floor["walls"]=result["walls"];return true;
    }
    public bool apply(Control owner,Resource source,bool preview)
    {var result=_buildings.update(Session(owner),Id(owner),source,"Edit floor plan",preview,false,new Settings());var errors=result["errors"].AsStringArray();if(errors.Length>0){Status(owner,errors[0]);return false;}var warnings=result["warnings"].AsStringArray();Status(owner,warnings.Length>0?string.Join(" · ",warnings):"Floor plan updated");return true;}
    public void cancel(Control owner){if(owner.Get("_drag").AsGodotDictionary().Count>0){Session(owner).Call("cancel");owner.Set("_drag",new Settings());}owner.QueueRedraw();}
}
