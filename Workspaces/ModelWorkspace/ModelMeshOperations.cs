using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;

public partial class ModelMeshOperations : RefCounted
{
    internal sealed class Snapshot
    {
        public readonly Vector3[] Vertices;
        public readonly int[][] Faces;
        public readonly Vector2[][] Uv;
        public readonly int[] Materials;
        public readonly bool Smooth;
        public Snapshot(Resource mesh)
        {Vertices=mesh.Get("vertices").AsVector3Array();Faces=mesh.Get("faces").AsGodotArray().Select(v=>v.AsInt32Array()).ToArray();Uv=mesh.Get("uv").AsGodotArray().Select(v=>v.AsVector2Array()).ToArray();Materials=mesh.Get("materials").AsInt32Array();Smooth=mesh.Get("smooth").AsBool();}
        public Vector3 Normal(int face)
        {
            Vector3 result=Vector3.Zero;int[] ids=Faces[face];
            for(int i=0;i<ids.Length;i++){Vector3 a=Vertices[ids[i]],b=Vertices[ids[(i+1)%ids.Length]];result+=new Vector3((a.Y-b.Y)*(a.Z+b.Z),(a.Z-b.Z)*(a.X+b.X),(a.X-b.X)*(a.Y+b.Y));}return -result.Normalized();
        }
        private readonly Dictionary<int,int[]> _triangles=new();
        public Vector3 Center(int face)
        {Vector3 result=Vector3.Zero;foreach(int index in Faces[face])result+=Vertices[index];return result/Math.Max(1,Faces[face].Length);}
        public Vector2 UvAt(int face,Vector3 point)
        {
            int[] indices=Triangles(face);Vector2 fallback=Vector2.Zero;
            for(int i=0;i<indices.Length;i+=3)
            {
                Vector3 a=Vertices[Faces[face][indices[i]]],u=Vertices[Faces[face][indices[i+1]]]-a,v=Vertices[Faces[face][indices[i+2]]]-a,p=point-a;
                double denominator=(double)u.Dot(u)*v.Dot(v)-(double)u.Dot(v)*u.Dot(v);if(Math.Abs(denominator)<.000000001)continue;
                float y=(float)(((double)v.Dot(v)*p.Dot(u)-(double)u.Dot(v)*p.Dot(v))/denominator),z=(float)(((double)u.Dot(u)*p.Dot(v)-(double)u.Dot(v)*p.Dot(u))/denominator);
                fallback=Uv[face][indices[i]]*(1-y-z)+Uv[face][indices[i+1]]*y+Uv[face][indices[i+2]]*z;if(y>=-.0001f&&z>=-.0001f&&y+z<=1.0001f)return fallback;
            }
            return fallback;
        }
        public int[] Triangles(int face)
        {
            if(_triangles.TryGetValue(face,out var cached))return cached;
            int[] ids=Faces[face];Vector3 n=Normal(face),u=n.Cross(Mathf.Abs(n.Y)<.9f?Vector3.Up:Vector3.Right).Normalized(),v=n.Cross(u);var points=ids.Select(index=>new Vector2(Vertices[index].Dot(u),Vertices[index].Dot(v))).ToArray();int[] result=Geometry2D.TriangulatePolygon(points);
            for(int i=0;i<result.Length;i+=3){Vector3 a=Vertices[ids[result[i]]],b=Vertices[ids[result[i+1]]],c=Vertices[ids[result[i+2]]];if((c-a).Cross(b-a).Dot(n)<0)(result[i+1],result[i+2])=(result[i+2],result[i+1]);}_triangles[face]=result;return result;
        }
    }
    private static Resource Empty()=>new KiwiModelMesh();
    public string edge_key(int a,int b)=>Math.Min(a,b)+":"+Math.Max(a,b);
    public Vector3 center(Vector3[] points)
    {Vector3 result=Vector3.Zero;foreach(Vector3 point in points)result+=point;return result/Math.Max(1,points.Length);}
    public Vector3 normal(Vector3[] points)
    {
        Vector3 result=Vector3.Zero;for(int i=0;i<points.Length;i++){Vector3 a=points[i],b=points[(i+1)%points.Length];result+=new Vector3((a.Y-b.Y)*(a.Z+b.Z),(a.Z-b.Z)*(a.X+b.X),(a.X-b.X)*(a.Y+b.Y));}return -result.Normalized();
    }
    public int[] triangles(Vector3[] points)
    {
        Vector3 n=normal(points),u=n.Cross(Mathf.Abs(n.Y)<.9f?Vector3.Up:Vector3.Right).Normalized(),v=n.Cross(u);int[] result=Geometry2D.TriangulatePolygon(points.Select(p=>new Vector2(p.Dot(u),p.Dot(v))).ToArray());
        for(int i=0;i<result.Length;i+=3){Vector3 a=points[result[i]],b=points[result[i+1]],c=points[result[i+2]];if((c-a).Cross(b-a).Dot(n)<0)(result[i+1],result[i+2])=(result[i+2],result[i+1]);}return result;
    }
    public Vector2 uv_at(Vector3[] points,Vector2[] uv,Vector3 point)
    {
        int[] indices=triangles(points);Vector2 fallback=Vector2.Zero;
        for(int i=0;i<indices.Length;i+=3)
        {
            Vector3 a=points[indices[i]],u=points[indices[i+1]]-a,v=points[indices[i+2]]-a,p=point-a;double denominator=(double)u.Dot(u)*v.Dot(v)-(double)u.Dot(v)*u.Dot(v);if(Math.Abs(denominator)<.000000001)continue;
            float y=(float)(((double)v.Dot(v)*p.Dot(u)-(double)u.Dot(v)*p.Dot(v))/denominator),z=(float)(((double)u.Dot(u)*p.Dot(v)-(double)u.Dot(v)*p.Dot(u))/denominator);
            fallback=uv[indices[i]]*(1-y-z)+uv[indices[i+1]]*y+uv[indices[i+2]]*z;if(y>=-.0001f&&z>=-.0001f&&y+z<=1.0001f)return fallback;
        }
        return fallback;
    }
    public Vector2[] face_uv(Vector3[] points)
    {int axis=(int)normal(points).Abs().MaxAxisIndex();return points.Select(p=>axis==0?new Vector2(p.Z,p.Y):axis==1?new Vector2(p.X,p.Z):new Vector2(p.X,p.Y)).ToArray();}
    public Godot.Collections.Array<Godot.Collections.Dictionary> edges(Resource source)
    {
        var faces=source.Get("faces").AsGodotArray();long signature=GD.Hash(faces);
        if(source.Get("_edge_signature").AsInt64()==signature)return source.Get("_edge_cache").AsGodotArray<Godot.Collections.Dictionary>();
        var data=faces.Select(value=>value.AsInt32Array()).ToArray();var result=new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach(var edge in ModelGeometryOperations.Edges(data))result.Add(new Godot.Collections.Dictionary{["a"]=edge.A,["b"]=edge.B,["faces"]=edge.Faces.ToArray()});
        source.Set("_edge_signature",signature);source.Set("_edge_cache",result);return result;
    }
    public string[] validate(Resource source,bool thorough)
    {
        var data=new Snapshot(source);var errors=new List<string>();if(data.Vertices.Any(point=>!point.IsFinite()))errors.Add("Non-finite vertex");
        if(data.Uv.Length!=data.Faces.Length||data.Materials.Length!=data.Faces.Length)errors.Add("Missing face surface data");
        for(int f=0;f<data.Faces.Length;f++)
        {
            int[] face=data.Faces[f];if(face.Length<3||face.Any(index=>index<0||index>=data.Vertices.Length)){errors.Add("Invalid face "+f);continue;}
            if(thorough&&(data.Normal(f).LengthSquared()<.5f||data.Triangles(f).Length==0))errors.Add("Degenerate face "+f);
            if(f<data.Uv.Length&&data.Uv[f].Length!=face.Length)errors.Add("Invalid UV corners");
        }
        return errors.ToArray();
    }
    public Resource copy_mesh(Resource source)
    {
        var data=new Snapshot(source);var result=Empty();result.Set("vertices",data.Vertices);result.Set("faces",new Godot.Collections.Array<int[]>(data.Faces));result.Set("uv",new Godot.Collections.Array<Vector2[]>(data.Uv));result.Set("materials",data.Materials);result.Set("smooth",data.Smooth);return result;
    }
    public Aabb bounds(Resource source)
    {var points=source.Get("vertices").AsVector3Array();Aabb result=points.Length>0?new Aabb(points[0],Vector3.Zero):new Aabb();foreach(Vector3 point in points) result=result.Expand(point);return result;}
    public ArrayMesh render_mesh(Resource source,Godot.Collections.Array<Material> surfaceMaterials)
    {
        var data=new Snapshot(source);var result=new ArrayMesh();if(data.Faces.Length==0)return result;var normals=new Vector3[data.Vertices.Length];var faceNormals=new Vector3[data.Faces.Length];
        for(int f=0;f<data.Faces.Length;f++){faceNormals[f]=data.Normal(f);if(data.Smooth)foreach(int vertex in data.Faces[f])normals[vertex]+=faceNormals[f];}
        if(data.Smooth)for(int i=0;i<normals.Length;i++)normals[i]=normals[i].Normalized();var groups=new Dictionary<int,List<int>>();
        for(int f=0;f<data.Faces.Length;f++){int material=f<data.Materials.Length?data.Materials[f]:0;if(!groups.TryGetValue(material,out var group)){group=new();groups[material]=group;}group.Add(f);}
        foreach(var group in groups)
        {
            using var builder=new SurfaceTool();builder.Begin(Mesh.PrimitiveType.Triangles);int count=0;
            foreach(int f in group.Value)foreach(int corner in data.Triangles(f))
            {int index=data.Faces[f][corner];builder.SetNormal(data.Smooth?normals[index]:faceNormals[f]);builder.SetUV(f<data.Uv.Length?data.Uv[f][corner]:Vector2.Zero);builder.AddVertex(data.Vertices[index]);count++;}
            if(count==0) continue;builder.GenerateTangents();builder.Commit(result);
            if(group.Key>=0&&group.Key<surfaceMaterials.Count)result.SurfaceSetMaterial(result.GetSurfaceCount()-1,surfaceMaterials[group.Key]);
        }
        return result;
    }
    public Resource from_mesh(Mesh? source)
    {
        var result=Empty();if(source==null)return result;var vertices=new List<Vector3>();var faces=new Godot.Collections.Array<int[]>();var uv=new Godot.Collections.Array<Vector2[]>();var materials=new List<int>();var lookup=new Dictionary<Vector3I,int>();
        for(int surface=0;surface<source.GetSurfaceCount();surface++)
        {
            if(source is ArrayMesh array&&array.SurfaceGetPrimitiveType(surface)!=Mesh.PrimitiveType.Triangles)continue;var arrays=source.SurfaceGetArrays(surface);if(arrays.Count==0)continue;
            Vector3[] points=arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();int[] ids=arrays[(int)Mesh.ArrayType.Index].VariantType==Variant.Type.Nil?Array.Empty<int>():arrays[(int)Mesh.ArrayType.Index].AsInt32Array();Vector2[] coords=arrays[(int)Mesh.ArrayType.TexUV].VariantType==Variant.Type.Nil?Array.Empty<Vector2>():arrays[(int)Mesh.ArrayType.TexUV].AsVector2Array();int count=ids.Length>0?ids.Length:points.Length;
            for(int i=0;i<count-2;i+=3)
            {
                var face=new int[3];var corners=new Vector2[3];
                for(int j=0;j<3;j++)
                {
                    int index=ids.Length>0?ids[i+j]:i+j;Vector3 p=points[index];var key=new Vector3I((int)Math.Round((double)p.X*100000,MidpointRounding.AwayFromZero),(int)Math.Round((double)p.Y*100000,MidpointRounding.AwayFromZero),(int)Math.Round((double)p.Z*100000,MidpointRounding.AwayFromZero));
                    if(!lookup.TryGetValue(key,out int vertex)){vertex=vertices.Count;lookup[key]=vertex;vertices.Add(p);}face[j]=vertex;corners[j]=index<coords.Length?coords[index]:Vector2.Zero;
                }
                if(face[0]!=face[1]&&face[1]!=face[2]&&face[0]!=face[2]){faces.Add(face);uv.Add(corners);materials.Add(surface);}
            }
        }
        result.Set("vertices",vertices.ToArray());result.Set("faces",faces);result.Set("uv",uv);result.Set("materials",materials.ToArray());return result;
    }
    public void append_mesh(Resource target,Resource other,Transform3D transform,int materialOffset)
    {
        var source=new Snapshot(other);Vector3[] old=target.Get("vertices").AsVector3Array();int offset=old.Length;var points=new Vector3[offset+source.Vertices.Length];Array.Copy(old,points,offset);for(int i=0;i<source.Vertices.Length;i++)points[offset+i]=transform*source.Vertices[i];target.Set("vertices",points);
        var faces=target.Get("faces").AsGodotArray();var uv=target.Get("uv").AsGodotArray();var materials=target.Get("materials").AsInt32Array().ToList();bool reverse=transform.Basis.Determinant()<0;
        for(int f=0;f<source.Faces.Length;f++)
        {int[] face=source.Faces[f].Select(index=>index+offset).ToArray();Vector2[] corners=source.Uv[f];if(reverse){Array.Reverse(face);Array.Reverse(corners);}faces.Add(face);uv.Add(corners);materials.Add(source.Materials[f]+materialOffset);}
        target.Set("materials",materials.ToArray());
    }
}
