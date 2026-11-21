using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class EnvironmentAssetOperations : RefCounted
{
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key,out var value) ? value : fallback;
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    public long content_stamp(Variant value, Settings seen, int depth, Settings revisions)
    {
        if (depth > 8) return Hash(value);
        if (value.VariantType == Variant.Type.String && FileAccess.FileExists(value.AsString()))
        {
            string path=value.AsString(); return Hash(new GArray {value,FileAccess.GetModifiedTime(path),Get(revisions,value,0)});
        }
        if (value.VariantType == Variant.Type.Array)
        {
            using var parts=new GArray(); foreach(var entry in value.AsGodotArray()) parts.Add(content_stamp(entry,seen,depth+1,revisions)); return Hash(parts);
        }
        if (value.VariantType == Variant.Type.Dictionary)
        {
            using var parts=new GArray(); foreach(var entry in value.AsGodotDictionary()) parts.Add(new GArray {entry.Key,content_stamp(entry.Value,seen,depth+1,revisions)}); return Hash(parts);
        }
        if (value.VariantType == Variant.Type.Object && value.AsGodotObject() is Resource resource)
        {
            long id=unchecked((long)resource.GetInstanceId()); if(seen.ContainsKey(id)) return Hash(id); seen[id]=true;
            using var parts=new GArray {id,content_stamp(resource.ResourcePath,seen,depth+1,revisions)};
            if(resource is Image || (resource is Texture2D && resource is not NoiseTexture2D && resource is not GradientTexture1D && resource is not GradientTexture2D)) return Hash(parts);
            foreach(var property in resource.GetPropertyList())
            {
                string name=property["name"].AsString(); if((property["usage"].AsInt64() & (long)PropertyUsageFlags.Storage)==0 || name is "script" or "resource_path" or "resource_name" or "resource_local_to_scene") continue;
                parts.Add(new GArray {property["name"],content_stamp(resource.Get(name),seen,depth+1,revisions)});
            }
            return Hash(parts);
        }
        return Hash(value);
    }
    public GArray model_parts(Resource source)
    {
        var parts=new GArray();
        foreach(var entry in source.Get("components").AsGodotArray())
        {
            var item=entry.As<Resource>(); var topology=item.Get("mesh").As<Resource>(); if(topology==null || !source.Call("visible_component",item).AsBool()) continue;
            var original=item.Get("geometry_source").As<Mesh>(); var modifiers=item.Get("modifiers").AsGodotArray();
            long geometry=Hash(new GArray {topology.Get("vertices"),topology.Get("faces"),topology.Get("uv"),topology.Get("materials")});
            // Historical C# importers stored signed hashes; compare the same 32 bits.
            bool unchanged=original!=null && modifiers.Count==0 && unchecked((uint)item.Get("geometry_source_hash").AsInt64())==unchecked((uint)geometry);
            Mesh? mesh;
            if(unchanged)
            {
                mesh=(Mesh)original!.Duplicate(); var materials=item.Get("surface_materials").AsGodotArray();
                for(int surface=0;surface<Math.Min(mesh.GetSurfaceCount(),materials.Count);surface++) mesh.SurfaceSetMaterial(surface,materials[surface].As<Material>());
            }
            else mesh=item.Call("render_mesh").As<Mesh>();
            if(mesh==null) continue;
            for(int surface=0;surface<mesh.GetSurfaceCount();surface++) if(mesh.SurfaceGetMaterial(surface) is ShaderMaterial authored)
                mesh.SurfaceSetMaterial(surface,GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("timeline_material",authored,false).As<Material>());
            if(mesh.GetSurfaceCount()>0) parts.Add(new Settings {["mesh"]=mesh,["transform"]=source.Call("world_transform",item),["name"]=item.Get("title")});
        }
        return parts;
    }
}
