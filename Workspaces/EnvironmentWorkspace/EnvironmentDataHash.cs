using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

/// <summary>Stable generated-data signatures across ResourceSaver key reordering.</summary>
public partial class EnvironmentDataHash : RefCounted
{
    public long value(Variant data) => unchecked((uint)GD.Hash(ordered(data,new Settings(),0)));
    public Variant ordered(Variant data,Settings seen,int depth)
    {
        if(depth>32) return "depth-limit";
        if(data.VariantType==Variant.Type.Dictionary)
        {
            var input=data.AsGodotDictionary(); var result=new GArray();
            foreach(var key in input.Keys.OrderBy(key=>key.AsString(),StringComparer.Ordinal)) result.Add(new GArray {key.AsString(),ordered(input[key],seen,depth+1)});
            return result;
        }
        if(data.VariantType==Variant.Type.Array)
        {var result=new GArray(); foreach(var item in data.AsGodotArray()) result.Add(ordered(item,seen,depth+1)); return result;}
        if(data.VariantType==Variant.Type.Object && data.AsGodotObject() is Resource resource)
        {
            if(resource is Script script) return new GArray {"script",script.ResourcePath};
            if(resource is Texture2D texture && texture is not NoiseTexture2D && texture is not GradientTexture1D && texture is not GradientTexture2D)
                return new GArray {resource.GetClass(),texture.GetWidth(),texture.GetHeight()};
            long id=unchecked((long)resource.GetInstanceId()); if(seen.TryGetValue(id,out var reference)) return new GArray {"reference",reference}; seen[id]=seen.Count;
            var properties=resource.GetPropertyList().Where(info=>(info["usage"].AsInt64() & (long)PropertyUsageFlags.Storage)!=0)
                .Select(info=>info["name"].AsString()).Where(name=>name is not ("script" or "resource_path" or "resource_local_to_scene" or "resource_scene_unique_id"))
                .OrderBy(name=>name,StringComparer.Ordinal);
            var result=new GArray {resource.GetClass(),resource.GetScript().As<Script>()?.ResourcePath ?? ""};
            foreach(string name in properties) result.Add(new GArray {name,ordered(resource.Get(name),seen,depth+1)}); return result;
        }
        return data;
    }
}
