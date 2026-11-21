using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class TerrainDataOperations
{
    private readonly TerrainMeshLod _lod=new();
    private static bool Cancelled(Settings state)=>Get(state,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",state).AsBool();
    private ArrayMesh Lod(Resource source,ArrayMesh mesh)
    {if(!source.Get("lod_enabled").AsBool())return mesh;var result=_lod.prepare(mesh)!;if(result!=mesh)mesh.Dispose();return result;}
    private static ArrayMesh Surfaces(Vector3[] vertices,Vector3[] normals,Vector2[] uv,List<int> baseIndices,List<int> paintIndices)
    {
        var mesh=new ArrayMesh();using var arrays=new GArray();arrays.Resize((int)Mesh.ArrayType.Max);arrays[(int)Mesh.ArrayType.Vertex]=vertices;arrays[(int)Mesh.ArrayType.Normal]=normals;arrays[(int)Mesh.ArrayType.TexUV]=uv;var slots=new List<int>();foreach(int slot in new[]{0,1}){var triangles=slot==0?baseIndices:paintIndices;if(triangles.Count==0)continue;arrays[(int)Mesh.ArrayType.Index]=triangles.ToArray();mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,arrays);slots.Add(slot);}mesh.SetMeta("environment_material_slots",slots.ToArray());return mesh;
    }
    public ArrayMesh volume_native_mesh(Resource source,Settings volume,bool cutaway,bool smoothPaint)
    {
        var data=ReadSamples(source);var baseIndices=new List<int>();var paintIndices=new List<int>();var indices=volume["indices"].AsInt32Array();var vertices=volume["vertices"].AsVector3Array();var kinds=Get(volume,"triangle_kind",Array.Empty<byte>()).AsByteArray();for(int index=0;index<indices.Length;index+=3)
        {
            if(cutaway&&kinds.Length>index/3&&kinds[index/3]==0)continue;int a=indices[index],b=indices[index+1],c=indices[index+2];var center=(vertices[a]+vertices[b]+vertices[c])/3;var point=((Vector2I)((new Vector2(center.X,center.Z)/data.Dimensions+Vector2.One*.5f)*(data.N-1)).Round()).Clamp(Vector2I.Zero,Vector2I.One*(data.N-1));var target=!smoothPaint&&data.Mask[point.X+point.Y*data.N]>=.5?paintIndices:baseIndices;target.Add(a);target.Add(b);target.Add(c);
        }
        return Surfaces(vertices,volume["normals"].AsVector3Array(),volume["uv"].AsVector2Array(),baseIndices,paintIndices);
    }
    public ArrayMesh chunk_mesh(Resource source,Vector2I chunk,bool cutaway,bool smoothPaint)
    {
        source.Call("prepare");using var stamp=new GArray {source.Call("chunk_geometry_key",chunk,!smoothPaint),cutaway,smoothPaint};long key=unchecked((uint)GD.Hash(stamp));var cache=source.Get("_chunk_cache").AsGodotDictionary();if(cache.TryGetValue(chunk,out var cached)&&cached.AsGodotDictionary()["key"].AsInt64()==key)return cached.AsGodotDictionary()["mesh"].As<ArrayMesh>();
        if(source.Call("needs_volume",chunk).AsBool())
        {
            var volume=Get(source.Get("volume_chunks").AsGodotDictionary(),chunk,new Settings()).AsGodotDictionary();if(volume.Count==0||Get(volume,"key",-1).AsInt64()!=PreparedVolumeKey(source,chunk)){source.Set("volume_status","Cave geometry needs generation.");return new ArrayMesh();}var volumeMesh=Lod(source,volume_native_mesh(source,volume,cutaway,smoothPaint));cache[chunk]=new Settings {["key"]=key,["mesh"]=volumeMesh};return volumeMesh;
        }
        var data=ReadSamples(source);var start=chunk*32;var count=new Vector2I(Math.Min(32,data.N-1-start.X),Math.Min(32,data.N-1-start.Y));if(count.X<=0||count.Y<=0)return new ArrayMesh();var vertices=new Vector3[(count.X+1)*(count.Y+1)];var normals=new Vector3[vertices.Length];var uv=new Vector2[vertices.Length];for(int z=0;z<=count.Y;z++)for(int x=0;x<=count.X;x++){int index=x+z*(count.X+1),px=start.X+x,pz=start.Y+z;vertices[index]=data.Position(px,pz);normals[index]=data.Normal(px,pz);uv[index]=new Vector2(px,pz)/(data.N-1);}var indices=new List<int>();var painted=new List<int>();for(int z=0;z<count.Y;z++)for(int x=0;x<count.X;x++){int a=x+z*(count.X+1),b=a+1,c=a+count.X+1,d=c+1,sample=start.X+x+(start.Y+z)*data.N;double amount=((double)data.Mask[sample]+data.Mask[sample+1]+data.Mask[sample+data.N]+data.Mask[sample+data.N+1])*.25;var target=!smoothPaint&&amount>=.5?painted:indices;target.AddRange(new[]{a,b,c,b,d,c});}var mesh=Lod(source,Surfaces(vertices,normals,uv,indices,painted));cache[chunk]=new Settings {["key"]=key,["mesh"]=mesh};return mesh;
    }
    public Resource? editable_mesh(Resource source,Settings cancellation)
    {
        source.Call("prepare");var data=ReadSamples(source);var mesh=new Topology {Smooth=true};int side=data.N<=257?data.N:129;for(int z=0;z<side;z++){if(Cancelled(cancellation))return null;int pz=(int)Math.Round(z/(double)(side-1)*(data.N-1),MidpointRounding.AwayFromZero);for(int x=0;x<side;x++){int px=(int)Math.Round(x/(double)(side-1)*(data.N-1),MidpointRounding.AwayFromZero);mesh.Points.Add(data.Position(px,pz));}}for(int z=0;z<side-1;z++){if(Cancelled(cancellation))return null;for(int x=0;x<side-1;x++){int a=x+z*side;mesh.AddFace(new[]{a,a+1,a+side});mesh.AddFace(new[]{a+1,a+side+1,a+side});}}return mesh.Build();
    }
}
