using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentCaveTool
{
    public bool path_input(RefCounted tool,InputEvent inputEvent,Settings info)
    {
        var canvas=Canvas(tool);var drag=State(tool,"_drag");var pose=info["transform"].AsTransform3D();
        if(inputEvent is InputEventMouseMotion motion&&drag.Count>0)
        {var ray=canvas.Call("ray",motion.Position).AsGodotDictionary();if(drag["plane"].AsPlane().IntersectsRay(ray["origin"].AsVector3(),ray["direction"].AsVector3()) is Vector3 hit){drag["position"]=pose.AffineInverse()*hit;canvas.Get("overlay").As<Control>().QueueRedraw();}return true;}
        if(inputEvent is not InputEventMouseButton button)return false;
        if(button.ButtonIndex==MouseButton.Left&&!button.Pressed&&drag.Count>0)
        {var cave=info["cave"].As<Resource>().Duplicate(true);set_point(cave,drag["path"].AsInt32(),drag["point"].AsInt32(),drag["position"].AsVector3());tool.Set("_drag",new Settings());canvas.EmitSignal("cave_replaced",info["id"].AsString(),cave);canvas.EmitSignal("gesture_finished");return true;}
        if(!button.Pressed||button.ButtonIndex is not (MouseButton.Left or MouseButton.Right))return false;
        Settings? nearest=null;double best=12;var camera=canvas.Get("camera").As<Camera3D>();
        foreach(var entry in points(info)){var handle=entry.AsGodotDictionary();var world=pose*handle["position"].AsVector3();if(camera.IsPositionBehind(world))continue;double distance=Project(canvas,world).DistanceTo(button.Position);if(distance<best){best=distance;nearest=handle;}}
        if(nearest!=null)
        {
            int pathIndex=nearest["path"].AsInt32(),pointIndex=nearest["point"].AsInt32();tool.Set("path_index",pathIndex);tool.Set("point_index",pointIndex);tool.Set("cave_id",info["cave"].As<Resource>().Get("cave_id"));canvas.GrabFocus();
            if(button.ButtonIndex==MouseButton.Right){var cave=info["cave"].As<Resource>().Duplicate(true);if(Remove(cave,pathIndex,pointIndex))canvas.EmitSignal("cave_replaced",info["id"].AsString(),cave);return true;}
            var world=pose*nearest["position"].AsVector3();tool.Set("_drag",new Settings {["path"]=pathIndex,["point"]=pointIndex,["position"]=nearest["position"],["plane"]=new Plane(camera.GlobalBasis.Z,world)});return true;
        }
        if(button.ButtonIndex==MouseButton.Left&&button.ShiftPressed)
        {
            var cave=info["cave"].As<Resource>().Duplicate(true);var paths=Paths(cave);if(paths.Count==0)return false;int chosen=Math.Clamp(tool.Get("path_index").AsInt32(),0,paths.Count-1);var path=paths[chosen].AsVector3Array().ToList();if(path.Count<2)return false;int edge=0;double distance=double.PositiveInfinity;
            for(int index=0;index<path.Count-1;index++){var a=Project(canvas,pose*path[index]);var b=Project(canvas,pose*path[index+1]);double candidate=button.Position.DistanceTo(Geometry2D.GetClosestPointToSegment(button.Position,a,b));if(candidate<distance){edge=index;distance=candidate;}}
            var plane=new Plane(camera.GlobalBasis.Z,pose*path[edge].Lerp(path[edge+1],.5f));var ray=canvas.Call("ray",button.Position).AsGodotDictionary();
            if(plane.IntersectsRay(ray["origin"].AsVector3(),ray["direction"].AsVector3()) is Vector3 hit){path.Insert(edge+1,pose.AffineInverse()*hit);paths[chosen]=path.ToArray();tool.Set("path_index",chosen);tool.Set("point_index",edge+1);canvas.EmitSignal("cave_replaced",info["id"].AsString(),cave);return true;}
        }
        return false;
    }
}
