using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderSampleCatalogOperations : RefCounted
{
    private static readonly object Gate=new();
    private static Godot.Collections.Array<Settings>? _entries;
    private static Godot.Collections.Array<Settings> Load()
    {
        if(_entries!=null)return _entries;using var parsed=Json.ParseString(ShaderLibraryData.Payload());if(parsed.VariantType!=Variant.Type.Array)throw new InvalidOperationException("The compiled shader library index is invalid.");var result=new Godot.Collections.Array<Settings>();
        foreach(var value in parsed.AsGodotArray())
        {
            var item=value.AsGodotDictionary().Duplicate(true);item["type"]=item["shader_type"];item["is_template"]=item["template"];item["supported_targets"]=item["targets"];item["preview"]=new Settings {["geometry"]=item["preview_mesh"],["animated"]=item["animated"],["requires_forward_plus"]=item["requires_forward_plus"]};result.Add(item);
        }
        _entries=result;return result;
    }
    public Godot.Collections.Array<Settings> get_entries(){lock(Gate)return Load().Duplicate(true);}
    public Settings get_entry(string id)
    {lock(Gate){foreach(var item in Load())if(item["id"].AsString()==id)return item.Duplicate(true);return new Settings();}}
    public string get_code(Variant entryOrId)
    {var item=entryOrId.VariantType==Variant.Type.Dictionary?entryOrId.AsGodotDictionary():get_entry(entryOrId.ToString());return item.TryGetValue("source",out var source)?source.AsString():"";}
    public Godot.Collections.Array<Settings> entries()=>get_entries();
    public Settings entry(string id)=>get_entry(id);
    internal static void ClearCache(){lock(Gate){_entries?.Clear();_entries=null;}}
}
