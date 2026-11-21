using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class RoadGeometryOperations : RefCounted
{
    public Vector3[] sample(Vector3[] points,double spacing)
    {
        var result=new List<Vector3>();if(points.Length<2)return result.ToArray();for(int index=0;index<points.Length-1;index++){var a=points[Math.Max(0,index-1)];var b=points[index];var c=points[index+1];var d=points[Math.Min(points.Length-1,index+2)];int count=Math.Clamp((int)Math.Ceiling(b.DistanceTo(c)/Math.Max(.25,spacing)),1,128);for(int step=0;step<count;step++){var point=b.CubicInterpolate(c,a,d,(float)step/count);if(result.Count==0||point.DistanceSquaredTo(result[^1])>.000001)result.Add(point);}}result.Add(points[^1]);return result.ToArray();
    }
    public Vector3[] trim(Vector3[] points,double start,double end)
    {
        var result=new List<Vector3>(points);for(int side=0;side<2;side++){if(side==1)result.Reverse();double distance=side==0?start:end;while(result.Count>2&&result[0].DistanceTo(result[1])<distance){distance-=result[0].DistanceTo(result[1]);result.RemoveAt(0);}if(result.Count>1)result[0]=result[0].MoveToward(result[1],(float)Math.Min(distance,result[0].DistanceTo(result[1])*.8));}if(result.Count>1)result.Reverse();return result.ToArray();
    }
    private static void Up(Topology mesh,int face)
    {if(ModelGeometryOperations.Normal(mesh.Points,mesh.Faces[face]).Y<0){Array.Reverse(mesh.Faces[face]);Array.Reverse(mesh.Uv[face]);}}
    internal Topology Strip(Vector3[] points,double width,double offset,Settings sections)
    {
        var mesh=new Topology();double distance=0;if(points.Length<2)return mesh;for(int index=0;index<points.Length;index++)
        {
            var before=(points[index]-points[Math.Max(0,index-1)]).Normalized();var after=(points[Math.Min(points.Length-1,index+1)]-points[index]).Normalized();var direction=(before+after).Normalized();direction.Y=0;direction=direction.Normalized();if(direction.IsZeroApprox())direction=Vector3.Forward;var sideways=new Vector3(-direction.Z,0,direction.X);var tangent=!after.IsZeroApprox()?after:before;tangent.Y=0;tangent=tangent.Normalized();var edgeNormal=new Vector3(-tangent.Z,0,tangent.X);double miter=1/Math.Max(.5,Math.Abs(sideways.Dot(edgeNormal)));Variant replacement=default;if(index==0)sections.TryGetValue("start",out replacement);else if(index==points.Length-1)sections.TryGetValue("end",out replacement);if(replacement.VariantType==Variant.Type.Vector3){sideways=replacement.AsVector3();miter=1;}foreach(double side in new[]{-.5,.5})mesh.Points.Add(points[index]+sideways*(float)(offset+width*side)*(float)miter);if(index==0)continue;double previous=distance;distance+=points[index].DistanceTo(points[index-1]);int basis=(index-1)*2;int face=mesh.AddFace(new[]{basis,basis+2,basis+3,basis+1},new[]{new Vector2(0,(float)(previous/width)),new Vector2(0,(float)(distance/width)),new Vector2(1,(float)(distance/width)),new Vector2(1,(float)(previous/width))});Up(mesh,face);
        }
        return mesh;
    }
    public Resource strip(Vector3[] points,double width,double offset,Settings sections)=>Strip(points,width,offset,sections).Build();
    public Resource junction(Vector3 center,GArray ends)
    {
        var profile=new List<Vector2>();var heights=new Dictionary<Vector2,float>();foreach(var value in ends){var end=value.AsGodotDictionary();var point=end["point"].AsVector3();var direction=end["direction"].AsVector3();var side=new Vector3(-direction.Z,0,direction.X).Normalized()*end["width"].AsSingle()*.5f;foreach(float sign in new[]{-1f,1f}){var coordinate=new Vector2(point.X+side.X*sign,point.Z+side.Z*sign);profile.Add(coordinate);heights[coordinate]=point.Y;}}var mesh=new Topology();if(profile.Count<3)return mesh.Build();profile=new List<Vector2>(Geometry2D.ConvexHull(profile.ToArray()));if(profile.Count>1&&profile[0].IsEqualApprox(profile[^1]))profile.RemoveAt(profile.Count-1);foreach(var point in profile)mesh.Points.Add(new Vector3(point.X,heights.TryGetValue(point,out float height)?height:center.Y,point.Y));var triangles=Geometry2D.TriangulatePolygon(profile.ToArray());for(int index=0;index<triangles.Length;index+=3)Up(mesh,mesh.AddFace(new[]{triangles[index],triangles[index+1],triangles[index+2]}));return mesh.Build();
    }
}
