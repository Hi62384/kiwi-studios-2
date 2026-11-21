using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainMeshLod : RefCounted
{
    public ArrayMesh? prepare(ArrayMesh? source)
    {
        if(source==null||source.GetSurfaceCount()==0) return source;
        using var importer=new ImporterMesh();int original=0;
        for(int surface=0;surface<source.GetSurfaceCount();surface++)
        {
            var arrays=source.SurfaceGetArrays(surface);
            if(arrays[(int)Mesh.ArrayType.Index].VariantType==Variant.Type.Nil)
            {using var builder=new SurfaceTool();builder.CreateFrom(source,surface);builder.Index();arrays=builder.CommitToArrays();}
            importer.AddSurface(Mesh.PrimitiveType.Triangles,arrays,new Godot.Collections.Array<GArray>(),new Settings(),source.SurfaceGetMaterial(surface));
            int[] indices=arrays[(int)Mesh.ArrayType.Index].VariantType==Variant.Type.Nil?System.Array.Empty<int>():arrays[(int)Mesh.ArrayType.Index].AsInt32Array();original+=indices.Length>0?indices.Length:arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array().Length;
        }
        ulong started=Time.GetTicksUsec();importer.GenerateLods(25,60,new GArray());var result=importer.GetMesh();var levels=new Godot.Collections.Array<Settings>();
        for(int surface=0;surface<importer.GetSurfaceCount();surface++)
        {var data=new Settings();for(int level=0;level<importer.GetSurfaceLodCount(surface);level++) data[importer.GetSurfaceLodSize(surface,level)]=importer.GetSurfaceLodIndices(surface,level);levels.Add(data);}
        foreach(StringName name in source.GetMetaList()) result.SetMeta(name,source.GetMeta(name));
        result.SetMeta("environment_lods",levels);result.SetMeta("environment_lod_base_indices",original);result.SetMeta("environment_lod_ms",(Time.GetTicksUsec()-started)/1000.0);return result;
    }
}
