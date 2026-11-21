using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWaterTool : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Control Canvas(RefCounted tool)=>tool.Get("canvas").As<Control>();
    private static GArray Rivers(Resource source)=>source.Get("manual_rivers").AsGodotArray();
    private static Settings Drag(RefCounted tool)=>tool.Get("_drag").AsGodotDictionary();
    private static int River(RefCounted tool)=>tool.Get("river_index").AsInt32();
    private static int Point(RefCounted tool)=>tool.Get("point_index").AsInt32();
    private static Vector2 Project(Control canvas,Vector3 point)=>canvas.Call("project",point).AsVector2();
    public Settings target(RefCounted tool)
    {
        var canvas=Canvas(tool);if(canvas==null)return new Settings();var session=canvas.Call("environment_session").As<RefCounted>();if(session==null)return new Settings();var selected=session.Call("primary").As<Resource>();if(selected==null)return new Settings();var terrain=session.Call("environment").As<Resource>().Call("terrain",selected.Get("id")).As<Resource>();var source=terrain?.Get("hydrology").As<Resource>();
        if(source==null||Rivers(source).Count==0)return new Settings();return new Settings {["id"]=selected.Get("id"),["terrain"]=terrain!,["source"]=source,["transform"]=session.Get("document").As<Resource>().Call("world_transform",selected)};
    }
    public Vector3[] path_points(Settings info,int index)
    {
        var source=info["source"].As<Resource>();var river=Rivers(source)[index].AsGodotDictionary();string id=Get(river,"id", "").AsString();var data=info["terrain"].As<Resource>().Get("water_data").AsGodotDictionary();
        foreach(var entry in Get(data,"paths",new GArray()).AsGodotArray()){var generated=entry.AsGodotDictionary();if(!Get(generated,"automatic",false).AsBool()&&Get(generated,"id", "").AsString()==id&&id.Length>0)return generated["points"].AsVector3Array();}return Get(river,"points",Array.Empty<Vector3>()).AsVector3Array();
    }
    public void draw(RefCounted tool)
    {
        var canvas=Canvas(tool);var drag=Drag(tool);if(canvas.Get("environment_tool").AsString()!="Water paths"){if(drag.Count>0)cancel(tool);return;}var info=target(tool);if(info.Count==0)return;
        var source=info["source"].As<Resource>();var pose=info["transform"].AsTransform3D();var camera=canvas.Get("camera").As<Camera3D>();var overlay=canvas.Get("overlay").As<Control>();
        for(int path=0;path<Rivers(source).Count;path++)
        {
            var points=path_points(info,path);var line=new List<Vector2>();
            for(int index=0;index<points.Length;index++)
            {
                var local=points[index];if(drag.Count>0&&path==River(tool)&&index==Point(tool))local=drag["position"].AsVector3();var world=pose*local;
                if(camera.IsPositionBehind(world)){if(line.Count>1)overlay.DrawPolyline(line.ToArray(),new Color("6dc9ff"),2,true);line.Clear();continue;}
                var screen=Project(canvas,world);line.Add(screen);overlay.DrawCircle(screen,7,new Color("10242f"));overlay.DrawCircle(screen,4.5f,new Color(path==River(tool)&&index==Point(tool)?"ffc678":"6dc9ff"));
            }
            if(line.Count>1)overlay.DrawPolyline(line.ToArray(),new Color("6dc9ff"),2,true);
        }
    }
    public bool input(RefCounted tool,InputEvent inputEvent)
    {
        var canvas=Canvas(tool);if(canvas.Get("environment_tool").AsString()!="Water paths")return false;var drag=Drag(tool);
        if((inputEvent is InputEventKey key&&key.Pressed&&(key.Keycode==Key.Escape||key.CtrlPressed&&key.Keycode is Key.Z or Key.Y))||(inputEvent is InputEventMouseButton right&&right.Pressed&&right.ButtonIndex==MouseButton.Right&&drag.Count>0)){if(drag.Count>0){cancel(tool);return true;}}
        if(canvas.Get("_navigating").AsBool()||canvas.Get("_panning").AsBool()||canvas.Get("_orbiting").AsBool())return false;var info=target(tool);if(info.Count==0)return false;var original=info["source"].As<Resource>();var pose=info["transform"].AsTransform3D();
        if(inputEvent is InputEventKey deletion&&deletion.Pressed&&deletion.Keycode is Key.Delete or Key.Backspace)return remove(tool,info);
        if(inputEvent is InputEventMouseMotion motion&&drag.Count>0)
        {
            var ray=canvas.Call("ray",motion.Position).AsGodotDictionary();if(drag["plane"].AsPlane().IntersectsRay(ray["origin"].AsVector3(),ray["direction"].AsVector3()) is Vector3 hit){var point=pose.AffineInverse()*hit;if(canvas.Get("snap").AsBool()!=motion.CtrlPressed)point=point.Snapped(Vector3.One*canvas.Get("grid_step").AsSingle());drag["position"]=point;canvas.Get("overlay").As<Control>().QueueRedraw();}return true;
        }
        if(inputEvent is not InputEventMouseButton button)return false;
        if(button.ButtonIndex==MouseButton.Left&&!button.Pressed&&drag.Count>0)
        {
            var next=original.Duplicate(true);var river=Rivers(next)[River(tool)].AsGodotDictionary();var points=river["points"].AsVector3Array();int index=Point(tool);if(index<0||index>=points.Length){cancel(tool);return true;}
            var position=drag["position"].AsVector3();if(Get(river,"follow_terrain",true).AsBool())position.Y=points[index].Y;bool changed=!position.IsEqualApprox(points[index]);points[index]=position;river["points"]=points;tool.Set("_drag",new Settings());if(changed)canvas.EmitSignal("water_replaced",info["id"].AsString(),next);canvas.EmitSignal("gesture_finished");return true;
        }
        if(!button.Pressed||button.ButtonIndex is not (MouseButton.Left or MouseButton.Right))return false;
        int nearestPath=-1,nearestPoint=0;var nearest=Vector3.Zero;double best=12;var camera=canvas.Get("camera").As<Camera3D>();
        for(int path=0;path<Rivers(original).Count;path++)
        {
            var points=path_points(info,path);for(int index=0;index<points.Length;index++){var world=pose*points[index];if(camera.IsPositionBehind(world))continue;double distance=Project(canvas,world).DistanceTo(button.Position);if(distance<best){best=distance;nearestPath=path;nearestPoint=index;nearest=points[index];}}
        }
        if(nearestPath>=0)
        {
            tool.Set("river_index",nearestPath);tool.Set("point_index",nearestPoint);canvas.GrabFocus();if(button.ButtonIndex==MouseButton.Right)return remove(tool,info);
            var world=pose*nearest;var normal=Get(Rivers(original)[nearestPath].AsGodotDictionary(),"follow_terrain",true).AsBool()?(pose.Basis*Vector3.Up).Normalized():camera.GlobalBasis.Z;tool.Set("_drag",new Settings {["position"]=nearest,["plane"]=new Plane(normal,world)});return true;
        }
        if(button.ButtonIndex==MouseButton.Left&&button.ShiftPressed)
        {
            var next=original.Duplicate(true);int path=Math.Clamp(River(tool),0,Rivers(next).Count-1);tool.Set("river_index",path);var points=path_points(info,path);if(points.Length<2)return false;int edge=0;double distance=double.PositiveInfinity;
            for(int index=0;index<points.Length-1;index++){var a=Project(canvas,pose*points[index]);var b=Project(canvas,pose*points[index+1]);double candidate=button.Position.DistanceTo(Geometry2D.GetClosestPointToSegment(button.Position,a,b));if(candidate<distance){edge=index;distance=candidate;}}
            var plane=new Plane((pose.Basis*Vector3.Up).Normalized(),pose*points[edge].Lerp(points[edge+1],.5f));var ray=canvas.Call("ray",button.Position).AsGodotDictionary();
            if(plane.IntersectsRay(ray["origin"].AsVector3(),ray["direction"].AsVector3()) is Vector3 hit){var river=Rivers(next)[path].AsGodotDictionary();var values=river["points"].AsVector3Array().ToList();values.Insert(edge+1,pose.AffineInverse()*hit);river["points"]=values.ToArray();tool.Set("point_index",edge+1);canvas.EmitSignal("water_replaced",info["id"].AsString(),next);}return true;
        }
        return false;
    }
    public bool remove(RefCounted tool,Settings info)
    {
        var next=info["source"].As<Resource>().Duplicate(true);int path=River(tool),index=Point(tool);if(path<0||path>=Rivers(next).Count)return true;var river=Rivers(next)[path].AsGodotDictionary();var points=river["points"].AsVector3Array().ToList();if(points.Count<=2||index<0||index>=points.Count)return true;points.RemoveAt(index);tool.Set("point_index",Math.Min(index,points.Count-1));river["points"]=points.ToArray();Canvas(tool).EmitSignal("water_replaced",info["id"].AsString(),next);return true;
    }
    public void cancel(RefCounted tool){tool.Set("_drag",new Settings());Canvas(tool).Get("overlay").As<Control>().QueueRedraw();}
}
