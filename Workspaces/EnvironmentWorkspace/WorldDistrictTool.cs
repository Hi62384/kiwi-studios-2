using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldDistrictTool : RefCounted
{
    public Control? canvas {get;set;}
    public Settings drag {get;set;}=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private WorldRoadTool Road=>canvas!.Get("road_tool").As<WorldRoadTool>();
    private CanvasItem Overlay=>canvas!.Get("overlay").As<CanvasItem>();
    public void cancel(){drag.Clear();if(canvas!=null)Overlay.QueueRedraw();}
    public Settings selection()
    {
        if(canvas==null)return new Settings();var info=Road.target();if(info.Count==0)return info;var selected=canvas.GetMeta("world_district_selection",new Settings()).AsGodotDictionary();if(Get(selected,"world","").AsString()!=info["id"].AsString())return new Settings();var settlements=info["source"].As<Resource>().Get("settlements").AsGodotArray();
        for(int settlement=0;settlement<settlements.Count;settlement++){var districts=Get(settlements[settlement].AsGodotDictionary(),"districts",new GArray()).AsGodotArray();for(int index=0;index<districts.Count;index++){var district=districts[index].AsGodotDictionary();if(district["id"].AsString()==Get(selected,"district","").AsString()){info["settlement"]=settlement;info["index"]=index;info["district"]=district;return info;}}}return new Settings();
    }
    public Vector3 _world(Settings info,Vector2 point)
    {double height=.08;var field=info["source"].As<Resource>().Get("terrain_field").As<RefCounted>();if(field!=null){var sample=field is WorldTerrainField native?native.sample(point):field.Call("sample",point).AsGodotDictionary();if(sample.Count>0)height=sample["height"].AsDouble()+.08;}return info["pose"].AsTransform3D()*new Vector3(point.X,(float)height,point.Y);}
    public void draw()
    {
        if(canvas==null)return;if(Road.Mode!="District boundary"){if(drag.Count>0)cancel();return;}var info=selection();if(info.Count==0){cancel();return;}var polygon=Get(drag,"polygon",info["district"].AsGodotDictionary()["polygon"]).AsVector2Array();var projected=new List<Vector2>();foreach(var point in polygon){var world=_world(info,point);if(Road.Camera.IsPositionBehind(world))return;projected.Add(Road.Project(world));}if(projected.Count<3)return;var points=projected.ToArray();if(Geometry2D.TriangulatePolygon(points).Length>0)Overlay.DrawColoredPolygon(points,new Color(.35f,.85f,.75f,.12f));projected.Add(projected[0]);Overlay.DrawPolyline(projected.ToArray(),new Color("75dfc5"),2,true);foreach(var point in points){Overlay.DrawCircle(point,6,new Color("10242f"));Overlay.DrawCircle(point,4,new Color("ffc678"));}
    }
    public bool input(InputEvent input)
    {
        if(canvas==null||Road.Mode!="District boundary")return false;if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){cancel();return true;}if(Road.Navigating)return false;var info=selection();if(info.Count==0)return false;var district=info["district"].AsGodotDictionary();if(drag.Count>0&&drag["district"].AsString()!=district["id"].AsString())cancel();
        if(input is InputEventMouseMotion motion&&drag.Count>0){var point=Road._position(info,motion.Position,Vector3.Zero,motion.CtrlPressed);if(point.VariantType==Variant.Type.Vector3){var polygon=drag["polygon"].AsVector2Array();int index=drag["point"].AsInt32();if(index<0||index>=polygon.Length){cancel();return true;}var local=point.AsVector3();polygon[index]=new Vector2(local.X,local.Z);drag["polygon"]=polygon;Overlay.QueueRedraw();}return true;}
        if(input is not InputEventMouseButton mouse)return false;if(mouse.ButtonIndex==MouseButton.Right&&drag.Count>0){cancel();return true;}if(mouse.ButtonIndex is not (MouseButton.Left or MouseButton.Right))return false;if(!mouse.Pressed){if(mouse.ButtonIndex==MouseButton.Left&&drag.Count>0){_commit(info,drag["polygon"].AsVector2Array());cancel();return true;}return false;}
        var points=district["polygon"].AsVector2Array();int nearest=-1;double distance=12;for(int index=0;index<points.Length;index++){var world=_world(info,points[index]);if(Road.Camera.IsPositionBehind(world))continue;double next=Road.Project(world).DistanceTo(mouse.Position);if(next<distance){distance=next;nearest=index;}}
        if(mouse.ButtonIndex==MouseButton.Right){if(nearest<0)return false;if(points.Length>3){var reduced=new List<Vector2>(points);reduced.RemoveAt(nearest);_commit(info,reduced.ToArray());}else canvas.EmitSignal("notice","A district needs at least three boundary points.");return true;}canvas.GrabFocus();if(nearest>=0){drag=new Settings {["district"]=district["id"],["polygon"]=points,["point"]=nearest};return true;}var positioned=Road._position(info,mouse.Position,Vector3.Zero,mouse.CtrlPressed);if(positioned.VariantType!=Variant.Type.Vector3)return true;var position=positioned.AsVector3();var localPoint=new Vector2(position.X,position.Z);int edge=0;double best=double.PositiveInfinity;for(int index=0;index<points.Length;index++){double value=localPoint.DistanceSquaredTo(Geometry2D.GetClosestPointToSegment(localPoint,points[index],points[(index+1)%points.Length]));if(value<best){best=value;edge=index;}}var expanded=new List<Vector2>(points);expanded.Insert(edge+1,localPoint);drag=new Settings {["district"]=district["id"],["polygon"]=expanded.ToArray(),["point"]=edge+1};Overlay.QueueRedraw();return true;
    }
    public void _commit(Settings info,Vector2[] polygon)
    {
        var district=info["district"].AsGodotDictionary();if(polygon.SequenceEqual(district["polygon"].AsVector2Array()))return;var next=new WorldSourceOperations().copy(info["source"].As<Resource>());var settlements=next.Get("settlements").AsGodotArray();int owner=info["settlement"].AsInt32(),index=info["index"].AsInt32();if(owner<0||owner>=settlements.Count)return;var settlement=settlements[owner].AsGodotDictionary();var districts=Get(settlement,"districts",new GArray()).AsGodotArray();if(index<0||index>=districts.Count)return;districts[index].AsGodotDictionary()["polygon"]=(Vector2[])polygon.Clone();var errors=new WorldDistrictOperations().validate(settlement);if(errors.Length>0){canvas!.EmitSignal("notice",errors[0]);return;}canvas!.EmitSignal("world_replaced",info["id"].AsString(),next);
    }
}
