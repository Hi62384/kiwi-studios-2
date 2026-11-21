using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldBlockOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Func<bool> Cancellation(Settings state)
    {if(!Get(state,"enabled",false).AsBool())return()=>false;var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_blocks.gd");return()=>bridge.Call("_cancel_requested",state).AsBool();}
    private sealed record Boundary(Vector3[] Points,string Source);
    private static Boundary[] Boundaries(GArray values)=>values.Select(value=>{var edge=value.AsGodotDictionary();return new Boundary(edge["points"].AsVector3Array(),edge["source"].AsString());}).ToArray();
    public Settings frontage(Vector2 point,GArray boundary)=>Frontage(point,Boundaries(boundary));
    private static Settings Frontage(Vector2 point,Boundary[] boundary)
    {
        double best=double.PositiveInfinity;var result=new Settings();foreach(var edge in boundary)for(int i=0;i<edge.Points.Length-1;i++){var a=edge.Points[i];var b=edge.Points[i+1];var closest=Geometry2D.GetClosestPointToSegment(point,new Vector2(a.X,a.Z),new Vector2(b.X,b.Z));double distance=point.DistanceSquaredTo(closest);if(distance<best){best=distance;result=new Settings {["point"]=closest,["source"]=edge.Source,["distance"]=distance};}}return result;
    }
    public Rect2 bounds(Vector2[] polygon)
    {var result=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)result=result.Expand(point);return result;}
    public double area(Vector2[] polygon)
    {double result=0;for(int i=0;i<polygon.Length;i++)result+=polygon[i].Cross(polygon[(i+1)%polygon.Length]);return result*.5;}
    public Vector2[] simplify(Vector2[] polygon)
    {var result=new List<Vector2>();for(int i=0;i<polygon.Length;i++){var before=polygon[i]-polygon[(i+polygon.Length-1)%polygon.Length];var after=polygon[(i+1)%polygon.Length]-polygon[i];if(before.Length()<.001||after.Length()<.001||before.Normalized().Dot(after.Normalized())>.99999)continue;result.Add(polygon[i]);}return result.ToArray();}
    public bool contains_rectangle(Vector2[] polygon,Transform3D pose,double width,double depth)
    {
        var rectangle=new List<Vector2>();foreach(var point in new[]{new Vector2((float)-width,(float)-depth),new Vector2((float)width,(float)-depth),new Vector2((float)width,(float)depth),new Vector2((float)-width,(float)depth)}){var transformed=pose*new Vector3(point.X*.5f,0,point.Y*.5f);var corner=new Vector2(transformed.X,transformed.Z);if(!Geometry2D.IsPointInPolygon(corner,polygon))return false;rectangle.Add(corner);}for(int side=0;side<4;side++)for(int edge=0;edge<polygon.Length;edge++)if(Geometry2D.SegmentIntersectsSegment(rectangle[side],rectangle[(side+1)%4],polygon[edge],polygon[(edge+1)%polygon.Length]).VariantType!=Variant.Type.Nil)return false;return true;
    }
    public Settings fit(Vector2[] polygon,GArray boundary,Settings cancellation)=>Fit(polygon,Boundaries(boundary),Cancellation(cancellation));
    private Settings Fit(Vector2[] polygon,Boundary[] boundary,Func<bool> cancelled)
    {
        var box=bounds(polygon);var candidates=new List<Vector2>{box.GetCenter()};var triangles=Geometry2D.TriangulatePolygon(polygon);for(int offset=0;offset<triangles.Length;offset+=Math.Max(3,triangles.Length/96*3))if(offset+2<triangles.Length)candidates.Add((polygon[triangles[offset]]+polygon[triangles[offset+1]]+polygon[triangles[offset+2]])/3);
        var best=new Settings();double bestArea=0;foreach(var center in candidates){if(cancelled())return new Settings();if(!Geometry2D.IsPointInPolygon(center,polygon))continue;var frontage=Frontage(center,boundary);if(frontage.Count==0)continue;var direction=frontage["point"].AsVector2()-center;if(direction.Length()<.01)continue;var pose=new Transform3D(Basis.LookingAt(new Vector3(direction.X,0,direction.Y).Normalized(),Vector3.Up),new Vector3(center.X,0,center.Y));double low=0,high=Math.Min(24,box.Size.Length());for(int step=0;step<12;step++){double scale=(low+high)*.5;if(contains_rectangle(polygon,pose,scale,scale*.9))low=scale;else high=scale;}double width=low*.92,depth=width*.9;if(width<4||depth<4||width*depth<=bestArea)continue;bestArea=width*depth;best=new Settings {["pose"]=pose,["width"]=width,["depth"]=depth,["frontage"]=frontage["source"],["distance"]=Math.Sqrt(frontage["distance"].AsDouble())};}return best;
    }
    public Godot.Collections.Array<Settings> plots(Settings block,Settings settlement,int budget,Settings cancellation)=>Plots(block,settlement,budget,Cancellation(cancellation));
    internal Godot.Collections.Array<Settings> Plots(Settings block,Settings settlement,int budget,Func<bool> cancelled)
    {
        var result=new Godot.Collections.Array<Settings>();var interior=Geometry2D.OffsetPolygon(block["polygon"].AsVector2Array(),(float)(-block["clearance"].AsDouble()-Get(settlement,"setback",2.0).AsDouble()));double lotSize=Math.Clamp(Get(settlement,"lot_size",18.0).AsDouble(),10,64);var boundary=Boundaries(block["boundary"].AsGodotArray());
        for(int pieceIndex=0;pieceIndex<interior.Count;pieceIndex++)
        {
            var piece=interior[pieceIndex];if(piece.Length<3||Math.Abs(area(piece))<36)continue;var box=bounds(piece);int columns=Math.Max(1,(int)Math.Ceiling(box.Size.X/lotSize)),rows=Math.Max(1,(int)Math.Ceiling(box.Size.Y/lotSize));var size=box.Size/new Vector2(columns,rows);
            for(int z=0;z<rows;z++){if(cancelled())return new Godot.Collections.Array<Settings>();for(int x=0;x<columns;x++){if(result.Count>=budget)return result;var start=box.Position+new Vector2(x,z)*size;var clipped=Geometry2D.IntersectPolygons(piece,new[]{start,start+new Vector2(size.X,0),start+size,start+new Vector2(0,size.Y)});for(int part=0;part<clipped.Count;part++){if(result.Count>=budget)return result;var polygon=clipped[part];if(Math.Abs(area(polygon))<25)continue;var fitted=Fit(polygon,boundary,cancelled);if(fitted.Count==0||fitted["distance"].AsDouble()>block["clearance"].AsDouble()+Get(settlement,"setback",2.0).AsDouble()+lotSize*.75)continue;string id=settlement["id"].AsString()+":"+block["id"].AsString()+":lot:"+pieceIndex+":"+x+":"+z+":"+part;result.Add(new Settings {["id"]=id,["settlement"]=settlement["id"],["block"]=block["id"],["polygon"]=polygon,["pose"]=fitted["pose"],["width"]=fitted["width"],["depth"]=fitted["depth"],["frontage"]=fitted["frontage"],["district"]="Residential",["reserved"]=false});}}}
        }
        return result;
    }
}
