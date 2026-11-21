using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class RoadStructureOperations : RefCounted
{
    private readonly RoadGeometryOperations _geometry=new();
    private readonly ModelModifiers _modifiers=new();
    private Topology Solid(Topology mesh,double depth)
    {using var input=mesh.Build();using var output=_modifiers.apply(input,new Settings {["type"]="Solidify",["amount"]=depth});return new Topology(new ModelMeshOperations.Snapshot(output));}
    public Settings bridge(Vector3[] points,double width,double pierHeight,Settings ground,Settings sections)
    {
        var deck=Solid(_geometry.Strip(points,width,0,sections),.3);var rail=new Topology();var supports=new Topology();double distance=0,nextPier=6;foreach(double sign in new[]{-1.0,1.0}){var bar=_geometry.Strip(points,.12,sign*(width*.5-.12),sections);for(int index=0;index<bar.Points.Count;index++)bar.Points[index]+=Vector3.Up*1.06f;rail.Append(Solid(bar,.12),Transform3D.Identity);}bool enabled=ground.TryGetValue("enabled",out var valid)&&valid.AsBool();var callback=enabled?GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/road_structures.gd"):null;
        for(int segment=0;segment<points.Length-1;segment++){var a=points[segment];var b=points[segment+1];double length=a.DistanceTo(b);if(length<.001)continue;var direction=(b-a).Normalized();var side=new Vector3(-direction.Z,0,direction.X).Normalized();var basis=Basis.LookingAt(direction,Vector3.Up);while(nextPier<=distance+length){var center=a.Lerp(b,(float)((nextPier-distance)/length));foreach(double sign in new[]{-1.0,1.0}){rail.Append(ModelPrimitives.Box(new Vector3(.12f,1,.12f)),new Transform3D(Basis.Identity,center+side*(float)sign*(float)(width*.5-.12)+Vector3.Up*.5f));var position=center+side*(float)sign*(float)width*.3f;double height=Math.Max(.3,pierHeight);if(enabled){var surface=callback!.Call("_ground_sample",ground,new Vector2(position.X,position.Z)).AsGodotDictionary();if(surface.Count==0)continue;height=position.Y-.3-surface["height"].AsDouble();if(height<.3)continue;}supports.Append(ModelPrimitives.Box(new Vector3(.6f,(float)height,.8f)),new Transform3D(basis,position-Vector3.Up*(float)(height*.5+.3)));}nextPier+=6;}distance+=length;}
        return new Settings {["deck"]=deck.Build(),["railings"]=rail.Build(),["supports"]=supports.Build()};
    }
    public Resource portals(Vector3[] points,double width,bool start,bool end,GArray frames)
    {
        var result=new Topology();var arch=new Topology();double center=(width*.65+2)*.5,radius=Math.Sqrt(Math.Pow(width*.5+.35,2)+center*center),left=Math.PI+Math.Asin(center/radius),right=-Math.Asin(center/radius);for(int segment=0;segment<24;segment++){double a=Mathf.Lerp(left,right,(double)segment/24),b=Mathf.Lerp(left,right,(double)(segment+1)/24);var profile=new List<Vector2>();foreach(var entry in new[]{new Vector2((float)a,(float)radius),new Vector2((float)a,(float)(radius+.35)),new Vector2((float)b,(float)(radius+.35)),new Vector2((float)b,(float)radius)})profile.Add(new Vector2((float)(Math.Cos(entry.X)*entry.Y),(float)Math.Max(0,center+Math.Sin(entry.X)*entry.Y)));var cell=ModelPrimitives.Prism(profile.ToArray(),.45,0,1);for(int index=0;index<cell.Points.Count;index++){var point=cell.Points[index];cell.Points[index]=new Vector3(point.X,point.Z,point.Y);}for(int face=0;face<cell.Faces.Count;face++){Array.Reverse(cell.Faces[face]);Array.Reverse(cell.Uv[face]);}arch.Append(cell,Transform3D.Identity);}
        if(frames.Count>0){foreach(var value in frames){var frame=value.AsGodotDictionary();var direction=frame["direction"].AsVector3();direction.Y=0;direction=direction.Normalized();result.Append(arch,new Transform3D(Basis.LookingAt(direction,Vector3.Up),frame["position"].AsVector3()));}return result.Build();}if(points.Length<2)return result.Build();foreach(int endpoint in new[]{0,points.Length-1}){if(endpoint==0&&!start||endpoint!=0&&!end)continue;var direction=(endpoint==0?points[1]-points[0]:points[^2]-points[^1]).Normalized();direction.Y=0;direction=direction.Normalized();result.Append(arch,new Transform3D(Basis.LookingAt(direction,Vector3.Up),points[endpoint]));}return result.Build();
    }
}
