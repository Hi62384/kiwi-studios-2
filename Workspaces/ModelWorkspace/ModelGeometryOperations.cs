using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class ModelGeometryOperations : RefCounted
{
    internal sealed class Topology
    {
        public readonly List<Vector3> Points=new();
        public readonly List<int[]> Faces=new();
        public readonly List<Vector2[]> Uv=new();
        public readonly List<int> Materials=new();
        public bool Smooth;
        public Topology(){}
        public Topology(ModelMeshOperations.Snapshot data){Points.AddRange(data.Vertices);Faces.AddRange(data.Faces);Uv.AddRange(data.Uv);Materials.AddRange(data.Materials);Smooth=data.Smooth;}
        public void Append(Topology other,Transform3D transform,int materialOffset=0)
        {
            int offset=Points.Count;foreach(Vector3 point in other.Points)Points.Add(transform*point);bool reverse=transform.Basis.Determinant()<0;
            for(int f=0;f<other.Faces.Count;f++){int[] face=other.Faces[f].Select(index=>index+offset).ToArray();Vector2[] corners=(Vector2[])other.Uv[f].Clone();if(reverse){Array.Reverse(face);Array.Reverse(corners);}AddFace(face,corners,other.Materials[f]+materialOffset);}
        }
        public int AddFace(int[] face,Vector2[]? corners=null,int material=0)
        {
            if(corners==null||corners.Length!=face.Length)
            {
                int dominant=(int)Normal(Points,face).Abs().MaxAxisIndex();corners=new Vector2[face.Length];
                for(int i=0;i<face.Length;i++){Vector3 p=Points[face[i]];corners[i]=dominant==0?new Vector2(p.Z,p.Y):dominant==1?new Vector2(p.X,p.Z):new Vector2(p.X,p.Y);}
            }
            Faces.Add(face);Uv.Add(corners);Materials.Add(material);return Faces.Count-1;
        }
        public Resource Build()
        {var result=new KiwiModelMesh();result.Set("vertices",Points.ToArray());result.Set("faces",new Godot.Collections.Array<int[]>(Faces));result.Set("uv",new Godot.Collections.Array<Vector2[]>(Uv));result.Set("materials",Materials.ToArray());result.Set("smooth",Smooth);return result;}
    }
    internal sealed record Edge(int A,int B,List<int> Faces);
    internal static List<Edge> Edges(int[][] faces)
    {
        var lookup=new Dictionary<(int,int),Edge>();
        for(int f=0;f<faces.Length;f++)for(int i=0;i<faces[f].Length;i++)
        {int a=faces[f][i],b=faces[f][(i+1)%faces[f].Length];var key=(Math.Min(a,b),Math.Max(a,b));if(!lookup.TryGetValue(key,out var edge)){edge=new Edge(key.Item1,key.Item2,new List<int>());lookup[key]=edge;}edge.Faces.Add(f);}
        return lookup.Values.ToList();
    }
    internal static Vector3 Normal(IReadOnlyList<Vector3> points,int[] ids)
    {
        Vector3 result=Vector3.Zero;for(int i=0;i<ids.Length;i++){Vector3 a=points[ids[i]],b=points[ids[(i+1)%ids.Length]];result+=new Vector3((a.Y-b.Y)*(a.Z+b.Z),(a.Z-b.Z)*(a.X+b.X),(a.X-b.X)*(a.Y+b.Y));}return -result.Normalized();
    }
    private static Resource Compact(ModelMeshOperations.Snapshot source,HashSet<int>? omitted)
    {
        var result=new Topology{Smooth=source.Smooth};var used=new Dictionary<int,int>();
        for(int f=0;f<source.Faces.Length;f++)
        {
            if(omitted?.Contains(f)==true)continue;var face=new int[source.Faces[f].Length];
            for(int i=0;i<face.Length;i++){int index=source.Faces[f][i];if(!used.TryGetValue(index,out int mapped)){mapped=result.Points.Count;used[index]=mapped;result.Points.Add(source.Vertices[index]);}face[i]=mapped;}
            result.Faces.Add(face);result.Uv.Add(source.Uv[f]);result.Materials.Add(source.Materials[f]);
        }
        return result.Build();
    }
    public Resource compact(Resource mesh)=>Compact(new ModelMeshOperations.Snapshot(mesh),null);
    public Resource remove_faces(Resource mesh,int[] selected)=>Compact(new ModelMeshOperations.Snapshot(mesh),new HashSet<int>(selected));
    public Resource weld(Resource mesh,double distance)
    {
        var data=new ModelMeshOperations.Snapshot(mesh);var result=new Topology{Smooth=data.Smooth};var lookup=new Dictionary<Vector3,int>();var mapping=new int[data.Vertices.Length];float step=(float)Math.Max(.000001,distance);
        for(int i=0;i<data.Vertices.Length;i++){Vector3 p=data.Vertices[i],key=p.Snapped(Vector3.One*step);if(!lookup.TryGetValue(key,out int mapped)){mapped=result.Points.Count;lookup[key]=mapped;result.Points.Add(p);}mapping[i]=mapped;}
        for(int f=0;f<data.Faces.Length;f++)
        {
            var face=new List<int>();var uv=new List<Vector2>();var seen=new HashSet<int>();
            for(int i=0;i<data.Faces[f].Length;i++){int mapped=mapping[data.Faces[f][i]];if(seen.Add(mapped)){face.Add(mapped);uv.Add(data.Uv[f][i]);}}
            if(face.Count<3)continue;int[] ids=face.ToArray();if(Normal(result.Points,ids).LengthSquared()<.5f)continue;result.Faces.Add(ids);result.Uv.Add(uv.ToArray());result.Materials.Add(data.Materials[f]);
        }
        return result.Build();
    }
    public Resource smooth_mesh(Resource mesh,double strength,int iterations)
    {
        var data=new ModelMeshOperations.Snapshot(mesh);var result=new Topology(data);var neighbors=new Dictionary<int,List<int>>();var boundary=new HashSet<int>();
        void Pair(int a,int b){if(!neighbors.TryGetValue(a,out var list)){list=new();neighbors[a]=list;}list.Add(b);}
        foreach(var edge in Edges(data.Faces)){Pair(edge.A,edge.B);Pair(edge.B,edge.A);if(edge.Faces.Count==1){boundary.Add(edge.A);boundary.Add(edge.B);}}
        for(int iteration=0;iteration<Math.Clamp(iterations,1,8);iteration++)
        {var points=result.Points.ToArray();foreach(var pair in neighbors){if(boundary.Contains(pair.Key))continue;Vector3 average=Vector3.Zero;foreach(int other in pair.Value)average+=points[other]/pair.Value.Count;result.Points[pair.Key]=points[pair.Key].Lerp(average,(float)Math.Clamp(strength,0,1));}}
        return result.Build();
    }
}
