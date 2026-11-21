using Godot;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModelNaturalRender : RefCounted
{
    private readonly ModelModifiers _modifiers=new();
    private readonly TerrainMeshLod _lod=new();
    public ArrayMesh prepare(ArrayMesh source,Resource item)
    {
        string kind=item.Get("generator").AsString();if(!ModelNaturalSettings.Accepts(kind)) return source;
        var collision=new List<Vector3>();
        if(!kind.StartsWith("Plant",System.StringComparison.Ordinal))
        {
            var topology=_modifiers.evaluate(item);var data=new ModelMeshOperations.Snapshot(topology);
            for(int face=0;face<data.Faces.Length;face++) if(data.Materials[face]==0)
                foreach(int index in data.Triangles(face)) collision.Add(data.Vertices[data.Faces[face][index]]);
        }
        source.SetMeta("kiwi_collision_faces",collision.ToArray());
        var optimized=_lod.prepare(source)!;var levels=optimized.GetMeta("environment_lods",new GArray()).AsGodotArray();var result=new ArrayMesh();
        for(int surface=0;surface<optimized.GetSurfaceCount();surface++)
        {
            var material=optimized.SurfaceGetMaterial(surface);if(material!=null&&material.GetMeta("kiwi_natural_foliage",false).AsBool()) levels[surface]=new Settings();
            result.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,optimized.SurfaceGetArrays(surface),new Godot.Collections.Array<GArray>(),levels[surface].AsGodotDictionary());result.SurfaceSetMaterial(surface,material);
        }
        foreach(StringName name in optimized.GetMetaList()) result.SetMeta(name,optimized.GetMeta(name));result.SetMeta("environment_lods",levels);return result;
    }
    public void time(Node root,double value,Settings visited)
    {
        if(!GodotObject.IsInstanceValid(root)) return;
        Mesh? mesh=root is MeshInstance3D instance?instance.Mesh:root is MultiMeshInstance3D multi?multi.Multimesh?.Mesh:null;
        if(mesh!=null)
        {
            for(int surface=0;surface<mesh.GetSurfaceCount();surface++)
            {
                Material? material=root is MeshInstance3D visual?visual.GetActiveMaterial(surface):((GeometryInstance3D)root).MaterialOverride??mesh.SurfaceGetMaterial(surface);
                if(material is not ShaderMaterial shader||visited.ContainsKey(shader.GetInstanceId())) continue;
                visited[shader.GetInstanceId()]=true;shader.SetMeta("kiwi_last_time",value);
                if(shader.HasMeta("kiwi_timeline_link")) shader.GetMeta("kiwi_timeline_link").AsGodotObject().Call("synchronize_parameters");
                string uniform=shader.GetMeta("kiwi_time_uniform","").AsString();if(uniform.Length>0) shader.SetShaderParameter(uniform,value);
            }
        }
        foreach(Node child in root.GetChildren()) time(child,value,visited);
    }
}
