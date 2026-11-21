using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentCaveTool : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Control Canvas(RefCounted tool)=>tool.Get("canvas").As<Control>();
    private static Settings State(RefCounted tool,string key)=>tool.Get(key).AsGodotDictionary();
    private static Vector2 Project(Control canvas,Vector3 point)=>canvas.Call("project",point).AsVector2();
    private static GArray Paths(Resource cave)=>cave.Get("paths").AsGodotArray();
    private static Settings Info(RefCounted session,Resource component,Resource cave)=>new() {["id"]=component.Get("id"),["cave"]=cave,["transform"]=session.Get("document").As<Resource>().Call("world_transform",component)};
    public Settings target(RefCounted tool)
    {
        var canvas=Canvas(tool);var session=canvas?.Call("environment_session").As<RefCounted>();if(session==null)return new Settings();var selected=session.Call("primary").As<Resource>();var environment=session.Call("environment").As<Resource>();string id=tool.Get("cave_id").AsString();
        var terrain=selected!=null?environment.Call("terrain",selected.Get("id")).As<Resource>():null;
        if(terrain!=null)
        {
            var caves=terrain.Get("caves").AsGodotArray();foreach(var value in caves){var cave=value.As<Resource>();if(id.Length==0||cave.Get("cave_id").AsString()==id){tool.Set("cave_id",cave.Get("cave_id"));return Info(session,selected!,cave);}}
            if(caves.Count>0){var cave=caves[0].As<Resource>();tool.Set("cave_id",cave.Get("cave_id"));return Info(session,selected!,cave);}return new Settings();
        }
        var seen=new HashSet<ulong>();foreach(var value in session.Get("document").As<Resource>().Get("components").AsGodotArray())
        {
            var component=value.As<Resource>();if(!seen.Add(component.GetInstanceId()))continue;terrain=environment.Call("terrain",component.Get("id")).As<Resource>();if(terrain==null)continue;
            foreach(var entry in terrain.Get("caves").AsGodotArray()){var cave=entry.As<Resource>();if(id.Length==0||cave.Get("cave_id").AsString()==id)return Info(session,component,cave);}
        }
        return new Settings();
    }
    public GArray points(Settings info)
    {
        var result=new GArray();var cave=info["cave"].As<Resource>();var paths=Paths(cave);
        for(int path=0;path<paths.Count;path++){var values=paths[path].AsVector3Array();for(int index=0;index<values.Length;index++)result.Add(new Settings {["path"]=path,["point"]=index,["position"]=values[index]});}
        var chambers=cave.Get("chambers").AsVector4Array();for(int index=0;index<chambers.Length;index++){var chamber=chambers[index];result.Add(new Settings {["path"]=-1,["point"]=index,["position"]=new Vector3(chamber.X,chamber.Y,chamber.Z)});}return result;
    }
    public void draw(RefCounted tool)
    {
        var canvas=Canvas(tool);string mode=canvas.Get("environment_tool").AsString();if(!mode.StartsWith("Cave ",StringComparison.Ordinal))return;var info=target(tool);if(info.Count==0)return;
        var cave=info["cave"].As<Resource>();var pose=info["transform"].AsTransform3D();var camera=canvas.Get("camera").As<Camera3D>();var overlay=canvas.Get("overlay").As<Control>();var drag=State(tool,"_drag");
        if(mode=="Cave path")
        {
            var paths=Paths(cave);for(int path=0;path<paths.Count;path++)
            {
                var values=paths[path].AsVector3Array();var line=new List<Vector2>();for(int index=0;index<values.Length;index++){var position=values[index];if(drag.Count>0&&drag["path"].AsInt32()==path&&drag["point"].AsInt32()==index)position=drag["position"].AsVector3();var world=pose*position;if(!camera.IsPositionBehind(world))line.Add(Project(canvas,world));}if(line.Count>1)overlay.DrawPolyline(line.ToArray(),new Color("6ddcc5"),2,true);
            }
            foreach(var entry in points(info))
            {
                var handle=entry.AsGodotDictionary();var position=handle["position"].AsVector3();if(drag.Count>0&&handle["path"].AsInt32()==drag["path"].AsInt32()&&handle["point"].AsInt32()==drag["point"].AsInt32())position=drag["position"].AsVector3();var world=pose*position;if(camera.IsPositionBehind(world))continue;var point=Project(canvas,world);bool selected=handle["path"].AsInt32()==tool.Get("path_index").AsInt32()&&handle["point"].AsInt32()==tool.Get("point_index").AsInt32();overlay.DrawCircle(point,7,new Color("10242f"));overlay.DrawCircle(point,4.5f,new Color(selected?"ffc678":"76e3c9"));
            }
        }
        else
        {
            var hit=State(tool,"_hit");if(hit.Count==0)return;var local=hit["local"].AsVector3();var normal=(pose.Basis.Transposed()*hit["normal"].AsVector3()).Normalized();var side=normal.Cross(Math.Abs(normal.Y)<.9?Vector3.Up:Vector3.Right).Normalized();var up=side.Cross(normal).Normalized();var ring=new Vector2[49];float radius=canvas.Get("brush_radius").AsSingle();
            for(int index=0;index<ring.Length;index++)ring[index]=Project(canvas,pose*(local+(side*(float)Math.Cos(index*Math.Tau/48)+up*(float)Math.Sin(index*Math.Tau/48))*radius));overlay.DrawPolyline(ring,new Color(mode=="Cave fill"?"ffb77c":"6ddcc5"),2,true);
        }
    }
    public void set_point(Resource cave,int pathIndex,int pointIndex,Vector3 point)
    {
        if(pathIndex<0){var chambers=cave.Get("chambers").AsVector4Array();if(pointIndex<0||pointIndex>=chambers.Length)return;chambers[pointIndex]=new Vector4(point.X,point.Y,point.Z,chambers[pointIndex].W);cave.Set("chambers",chambers);}
        else{var paths=Paths(cave);if(pathIndex>=paths.Count)return;var values=paths[pathIndex].AsVector3Array();if(pointIndex<0||pointIndex>=values.Length)return;values[pointIndex]=point;paths[pathIndex]=values;}
    }
    private static bool Remove(Resource cave,int pathIndex,int pointIndex)
    {
        if(pathIndex<0){var chambers=cave.Get("chambers").AsVector4Array().ToList();if(pointIndex<0||pointIndex>=chambers.Count)return false;chambers.RemoveAt(pointIndex);cave.Set("chambers",chambers.ToArray());return true;}
        var paths=Paths(cave);if(pathIndex>=paths.Count)return false;var points=paths[pathIndex].AsVector3Array().ToList();if(pointIndex<0||pointIndex>=points.Count||points.Count<=2)return false;points.RemoveAt(pointIndex);paths[pathIndex]=points.ToArray();return true;
    }
    public void cancel(RefCounted tool){tool.Set("_drag",new Settings());tool.Set("_stroke",new Settings());tool.Set("_hit",new Settings());Canvas(tool).Get("overlay").As<Control>().QueueRedraw();}
}
