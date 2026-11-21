using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class ModelGeometryOperations
{
    private static int Vertex(Topology mesh,Dictionary<Vector3,int> lookup,Vector3 point)
    {var key=point.Snapped(Vector3.One*.00001f);if(!lookup.TryGetValue(key,out int index)){index=mesh.Points.Count;lookup[key]=index;mesh.Points.Add(point);}return index;}
    public Resource clip_plane(Resource mesh,Vector3 normal,double distance)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);var result=new Topology{Smooth=source.Smooth};var cut=new List<Vector3>();var lookup=new Dictionary<Vector3,int>();
        for(int f=0;f<source.Faces.Length;f++)
        {
            int[] face=source.Faces[f];var points=new List<Vector3>();var coords=new List<Vector2>();
            for(int i=0;i<face.Length;i++)
            {
                int j=(i+1)%face.Length;Vector3 a=source.Vertices[face[i]],b=source.Vertices[face[j]];double da=normal.Dot(a)-distance,db=normal.Dot(b)-distance;
                if(da<=.000001){points.Add(a);coords.Add(source.Uv[f][i]);}if(Math.Abs(da)<.000001)cut.Add(a);
                if((da<-.000001&&db>.000001)||(da>.000001&&db<-.000001)){float t=(float)(da/(da-db));Vector3 p=a.Lerp(b,t);points.Add(p);coords.Add(source.Uv[f][i].Lerp(source.Uv[f][j],t));cut.Add(p);}
            }
            if(points.Count>=3)result.AddFace(points.Select(point=>Vertex(result,lookup,point)).ToArray(),coords.ToArray(),source.Materials[f]);
        }
        var unique=new List<Vector3>();var used=new HashSet<Vector3>();foreach(Vector3 point in cut)if(used.Add(point.Snapped(Vector3.One*.00001f)))unique.Add(point);
        if(unique.Count>=3)
        {
            Vector3 center=Vector3.Zero;foreach(Vector3 point in unique)center+=point/unique.Count;Vector3 u=normal.Cross(Mathf.Abs(normal.Y)<.9f?Vector3.Up:Vector3.Right).Normalized(),v=normal.Cross(u);
            unique=unique.OrderByDescending(point=>Math.Atan2((point-center).Dot(v),(point-center).Dot(u))).ToList();int[] cap=unique.Select(point=>Vertex(result,lookup,point)).ToArray();int f=result.AddFace(cap);
            if(Normal(result.Points,cap).Dot(normal)<0){Array.Reverse(result.Faces[f]);Array.Reverse(result.Uv[f]);}
        }
        return result.Build();
    }
    private static bool Convex(ModelMeshOperations.Snapshot mesh)
    {for(int f=0;f<mesh.Faces.Length;f++){Vector3 n=mesh.Normal(f);float d=n.Dot(mesh.Center(f));foreach(Vector3 point in mesh.Vertices)if(n.Dot(point)>d+.0001)return false;}return true;}
    public bool convex(Resource mesh)=>Convex(new ModelMeshOperations.Snapshot(mesh));
    private sealed record Plane(Vector3 Normal,double Distance,int Material,int Face);
    public Resource? bevel(Resource mesh,int[] selectedEdges,double width)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);if(source.Faces.Length>64||!Convex(source))return null;
        var planes=new List<Plane>();var edges=Edges(source.Faces);var unique=new HashSet<(Vector3,double)>();
        for(int f=0;f<source.Faces.Length;f++)
        {Vector3 n=source.Normal(f);double d=n.Dot(source.Center(f));var key=(n.Snapped(Vector3.One*.00001f),Math.Floor(d/.00001+.5)*.00001);if(unique.Add(key))planes.Add(new Plane(n,d,source.Materials[f],f));}
        var selected=new HashSet<int>(selectedEdges);
        for(int i=0;i<edges.Count;i++)
        {
            if(selected.Count>0&&!selected.Contains(i))continue;var edge=edges[i];if(edge.Faces.Count!=2)continue;Vector3 a=source.Normal(edge.Faces[0]),b=source.Normal(edge.Faces[1]);if(a.Dot(b)>.999)continue;Vector3 n=(a+b).Normalized();planes.Add(new Plane(n,n.Dot(source.Vertices[edge.A])-Math.Max(.0001,width),source.Materials[edge.Faces[0]],-1));
        }
        if(planes.Count>64)return null;var result=new Topology();var lookup=new Dictionary<Vector3,int>();
        for(int i=0;i<planes.Count;i++)for(int j=i+1;j<planes.Count;j++)for(int k=j+1;k<planes.Count;k++)
        {
            Vector3 a=planes[i].Normal,b=planes[j].Normal,c=planes[k].Normal;double determinant=a.Dot(b.Cross(c));if(Math.Abs(determinant)<.000001)continue;
            Vector3 point=(b.Cross(c)*(float)planes[i].Distance+c.Cross(a)*(float)planes[j].Distance+a.Cross(b)*(float)planes[k].Distance)/(float)determinant;
            if(planes.All(plane=>plane.Normal.Dot(point)<=plane.Distance+.00001))Vertex(result,lookup,point);
        }
        foreach(var plane in planes)
        {
            var indices=new List<int>();Vector3 center=Vector3.Zero;
            for(int i=0;i<result.Points.Count;i++)if(Math.Abs(plane.Normal.Dot(result.Points[i])-plane.Distance)<.00005){indices.Add(i);center+=result.Points[i];}
            if(indices.Count<3)continue;center/=indices.Count;Vector3 n=plane.Normal,u=n.Cross(Mathf.Abs(n.Y)<.9f?Vector3.Up:Vector3.Right).Normalized(),v=n.Cross(u);
            int[] face=indices.OrderByDescending(index=>Math.Atan2((result.Points[index]-center).Dot(v),(result.Points[index]-center).Dot(u))).ToArray();Vector2[]? coordinates=plane.Face>=0?face.Select(index=>source.UvAt(plane.Face,result.Points[index])).ToArray():null;int added=result.AddFace(face,coordinates,plane.Material);
            if(Normal(result.Points,face).Dot(n)<0){Array.Reverse(result.Faces[added]);Array.Reverse(result.Uv[added]);}
        }
        return result.Build();
    }
}
