using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class ModelGeometryOperations
{
    public Settings extrude(Resource mesh,int[] selected,double distance,bool individual)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);var result=new Topology(source);var mapping=new Dictionary<(int,int),int>();var normals=new Dictionary<(int,int),Vector3>();var chosen=new List<int>();var selectedSet=new HashSet<int>(selected);
        (int,int) Key(int face,int vertex)=>(individual?face:-1,vertex);
        foreach(int f in selected)
        {if(f<0||f>=source.Faces.Length)continue;foreach(int index in source.Faces[f]){var key=Key(f,index);normals[key]=normals.GetValueOrDefault(key)+source.Normal(f);}}
        foreach(int f in selected)
        {
            if(f<0||f>=source.Faces.Length)continue;var old=source.Faces[f];var cap=new int[old.Length];
            for(int i=0;i<old.Length;i++){int index=old[i];var key=Key(f,index);if(!mapping.TryGetValue(key,out int mapped)){mapped=result.Points.Count;mapping[key]=mapped;result.Points.Add(source.Vertices[index]+normals[key].Normalized()*(float)distance);}cap[i]=mapped;}
            result.Faces[f]=cap;chosen.Add(f);
        }
        foreach(var edge in Edges(source.Faces))
        {
            int[] adjacent=edge.Faces.Where(selectedSet.Contains).ToArray();if(adjacent.Length==0||(adjacent.Length>1&&!individual))continue;
            foreach(int f in adjacent)
            {
                int[] face=source.Faces[f];int a=edge.A,b=edge.B;if(face[(Array.IndexOf(face,a)+1)%face.Length]!=b)(a,b)=(b,a);
                result.AddFace(new[]{a,b,mapping[Key(f,b)],mapping[Key(f,a)]},new[]{Vector2.Zero,Vector2.Right,new Vector2(1,(float)distance),new Vector2(0,(float)distance)},source.Materials[f]);
            }
        }
        return new Settings{["mesh"]=result.Build(),["selection"]=chosen.ToArray()};
    }
    public Settings inset(Resource mesh,int[] selected,double width)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);var result=new Topology(source);var chosen=new List<int>();
        foreach(int f in selected)
        {
            if(f<0||f>=source.Faces.Length)continue;int[] face=source.Faces[f];Vector3 normal=source.Normal(f);var cap=new int[face.Length];var capUv=new Vector2[face.Length];
            for(int i=0;i<face.Length;i++)
            {
                Vector3 current=source.Vertices[face[i]],previous=source.Vertices[face[(i+face.Length-1)%face.Length]],next=source.Vertices[face[(i+1)%face.Length]];
                Vector3 a=(current-previous).Normalized().Cross(normal),b=(next-current).Normalized().Cross(normal),bisector=(a+b).Normalized();double distance=Math.Min(Math.Max(0,width),Math.Min(current.DistanceTo(previous),current.DistanceTo(next))*.45);
                Vector3 offset=bisector*(float)(distance/Math.Max(.1,Mathf.Abs(bisector.Dot(b))));cap[i]=result.Points.Count;result.Points.Add(current+offset);capUv[i]=source.UvAt(f,current+offset);
            }
            result.Faces[f]=cap;result.Uv[f]=capUv;chosen.Add(f);
            for(int i=0;i<face.Length;i++){int j=(i+1)%face.Length;result.AddFace(new[]{face[i],face[j],cap[j],cap[i]},new[]{source.Uv[f][i],source.Uv[f][j],capUv[j],capUv[i]},source.Materials[f]);}
        }
        return new Settings{["mesh"]=result.Build(),["selection"]=chosen.ToArray()};
    }
    private static (int,int) EdgeKey(int a,int b)=>(Math.Min(a,b),Math.Max(a,b));
    private static void ExpandedFace(Topology result,ModelMeshOperations.Snapshot source,int f,Dictionary<(int,int),int> midpoints)
    {
        var face=new List<int>();var coordinates=new List<Vector2>();int[] old=source.Faces[f];
        for(int i=0;i<old.Length;i++){int j=(i+1)%old.Length;face.Add(old[i]);coordinates.Add(source.Uv[f][i]);if(midpoints.TryGetValue(EdgeKey(old[i],old[j]),out int midpoint)){face.Add(midpoint);coordinates.Add((source.Uv[f][i]+source.Uv[f][j])*.5f);}}
        result.AddFace(face.ToArray(),coordinates.ToArray(),source.Materials[f]);
    }
    public Resource subdivide(Resource mesh,int[] selected)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);var result=new Topology{Smooth=source.Smooth};result.Points.AddRange(source.Vertices);var midpoints=new Dictionary<(int,int),int>();var selectedSet=new HashSet<int>(selected);
        int Mid(int a,int b){var key=EdgeKey(a,b);if(!midpoints.TryGetValue(key,out int index)){index=result.Points.Count;midpoints[key]=index;result.Points.Add((source.Vertices[a]+source.Vertices[b])*.5f);}return index;}
        foreach(var edge in Edges(source.Faces))if(selected.Length==0||edge.Faces.Any(selectedSet.Contains))Mid(edge.A,edge.B);
        for(int f=0;f<source.Faces.Length;f++)
        {
            if(selected.Length>0&&!selectedSet.Contains(f)){ExpandedFace(result,source,f,midpoints);continue;}
            int[] face=source.Faces[f];int midpoint=result.Points.Count;result.Points.Add(source.Center(f));Vector2 centerUv=Vector2.Zero;foreach(Vector2 corner in source.Uv[f])centerUv+=corner/face.Length;
            for(int i=0;i<face.Length;i++)
            {int previous=(i+face.Length-1)%face.Length,next=(i+1)%face.Length;result.AddFace(new[]{face[i],Mid(face[i],face[next]),midpoint,Mid(face[i],face[previous])},new[]{source.Uv[f][i],(source.Uv[f][i]+source.Uv[f][next])*.5f,centerUv,(source.Uv[f][i]+source.Uv[f][previous])*.5f},source.Materials[f]);}
        }
        return result.Build();
    }
    public Resource subdivide_edges(Resource mesh,int[] selected)
    {
        var source=new ModelMeshOperations.Snapshot(mesh);var result=new Topology{Smooth=source.Smooth};result.Points.AddRange(source.Vertices);var midpoints=new Dictionary<(int,int),int>();var edges=Edges(source.Faces);
        foreach(int index in selected){if(index<0||index>=edges.Count)continue;var edge=edges[index];midpoints[EdgeKey(edge.A,edge.B)]=result.Points.Count;result.Points.Add((source.Vertices[edge.A]+source.Vertices[edge.B])*.5f);}
        for(int f=0;f<source.Faces.Length;f++)ExpandedFace(result,source,f,midpoints);return result.Build();
    }
}
