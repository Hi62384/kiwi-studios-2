using Godot;
using System;
using System.Globalization;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class EnvironmentAssetOperations
{
    private readonly ModelImport _import = new();
    private readonly GrowthMaterialOperations _growthMaterials = new();
    private static bool ScriptType(GodotObject value,string path)
    { var script=value.GetScript().As<Script>(); while(script!=null) {if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script=script.GetBaseScript();} return false; }
    private static string Normalize(string path) => ProjectSettings.GlobalizePath(path).Replace('\\','/').SimplifyPath();
    private static Resource? Resolve(Resource? source) => source==null ? null : GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("resolve_reference",source).As<Resource>();
    private static Settings Failure(string message) => new() { ["parts"]=new GArray(),["error"]=message,["key"]=0 };
    private static void Store(Settings cache,Variant key,Variant value)
    { if(cache.Count>=64) cache.Remove(cache.Keys.First()); cache[key]=value; }
    public void invalidate(string path,Settings cache,Settings revisions,Settings materials)
    {
        revisions[path]=Get(revisions,path,0).AsInt64()+1; string target=Normalize(path);
        if(target!=path) revisions[target]=Get(revisions,target,0).AsInt64()+1;
        foreach(var source in cache.Keys.ToArray())
        {
            var data=cache[source].AsGodotDictionary();
            if(Normalize(source.AsString())!=target && !Get(data,"dependencies",new GArray()).AsGodotArray().Contains(target)) continue;
            if(source.AsString()!=path) revisions[source]=Get(revisions,source,0).AsInt64()+1;
            cache.Remove(source);
        }
        materials.Clear();
    }
    public Settings load_parts(string path,Settings cache,Settings revisions)
    {
        if(path.Length==0 || !FileAccess.FileExists(path)) return Failure("Missing model: "+path);
        string extension=path.GetExtension().ToLowerInvariant();
        if(extension is "tres" or "res" && ResourceLoader.Load(path) is Resource resource && ScriptType(resource,"res://Workspaces/EnvironmentWorkspace/environment_document.gd"))
            return Failure("Open this environment in Environment Creator or use it as a linked Scene environment asset.");
        using var file=FileAccess.Open(path,FileAccess.ModeFlags.Read);
        long key=Hash(new GArray {path,FileAccess.GetModifiedTime(path),file?.GetLength() ?? 0,Get(revisions,path,0)});
        if(cache.TryGetValue(path,out var cached) && cached.AsGodotDictionary()["key"].AsInt64()==key) return cached.AsGodotDictionary();
        var source=_import.load_document(path);
        var linked=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").Call("resolve",source).AsGodotDictionary();
        source=Get(linked,"document").As<Resource>() ?? source;
        var parts=model_parts(source);
        var result=new Settings {["parts"]=parts,["key"]=key,["dependencies"]=Get(linked,"dependencies",new GArray()),["error"]=parts.Count>0 ? "" : "The source has no supported mesh surfaces: "+path};
        Store(cache,path,result); return result;
    }
    public Settings load_scatter_parts(Variant value,Settings cache,Settings revisions)
    {
        if(value.VariantType!=Variant.Type.Object || value.AsGodotObject() is not Resource source || !ScriptType(source,"res://Workspaces/ModelWorkspace/model_document.gd")) return load_parts(value.AsString(),cache,revisions);
        if(ScriptType(source,"res://Workspaces/EnvironmentWorkspace/environment_document.gd")) return Failure("Use a native Model resource for an embedded scatter palette.");
        long key=content_stamp(value,new Settings(),0,revisions); string identity="inline:"+unchecked((long)source.GetInstanceId()).ToString(CultureInfo.InvariantCulture);
        if(cache.TryGetValue(identity,out var cached) && cached.AsGodotDictionary()["key"].AsInt64()==key) return cached.AsGodotDictionary();
        var parts=model_parts(source); var result=new Settings {["parts"]=parts,["key"]=key,["error"]=parts.Count>0 ? "" : "The embedded model has no visible mesh geometry."}; Store(cache,identity,result); return result;
    }
    public Material? material(Variant value,Settings cache,Settings revisions)
    {
        long key=content_stamp(value,new Settings(),0,revisions); if(cache.TryGetValue(key,out var cached)) return cached.As<Material>();
        var result=raw_material(value);
        if(result is ShaderMaterial) result=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("timeline_material",result,false).As<Material>();
        Store(cache,key,result!=null ? Variant.From(result) : default); return result;
    }
    public Material? raw_material(Variant value)
    {
        Resource? resource=value.VariantType==Variant.Type.Object ? value.AsGodotObject() as Resource : null;
        if(value.VariantType==Variant.Type.String)
        {
            string path=value.AsString(); string extension=path.GetExtension().ToLowerInvariant();
            if(extension is "png" or "jpg" or "jpeg" or "webp" or "bmp" or "tga" or "exr" or "hdr")
            {
                var image=GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("image_from_value",value).As<Image>();
                return image==null || image.IsEmpty() ? null : new StandardMaterial3D {AlbedoTexture=ImageTexture.CreateFromImage(image),Uv1Triplanar=true};
            }
            if(path.Length>0 && ResourceLoader.Exists(path)) resource=ResourceLoader.Load(path);
        }
        if(resource==null) return null;
        if(ScriptType(resource,"res://scripts/actors/core/actor_object_reference.gd")) resource=Resolve(resource);
        if(resource==null) return null;
        if(ScriptType(resource,"res://scripts/actors/core/actor_object_data.gd") && resource.Get("type_id").AsString() is "image" or "noise_image")
            return new StandardMaterial3D {AlbedoTexture=GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("texture_for_object",resource).As<Texture2D>(),Uv1Triplanar=true};
        if(resource is Texture2D texture) return new StandardMaterial3D {AlbedoTexture=texture,Uv1Triplanar=true};
        return _growthMaterials.from_asset(resource);
    }
    public long world_stamp(Resource document,Settings revisions)
    {
        var resolved=Resolve(document.Get("atmosphere").As<Resource>()); var climate=document.Get("climate").As<Resource>();
        return Hash(new GArray {document.Get("environment_id"),content_stamp(document.Get("environment_source"),new Settings(),0,revisions),content_stamp(resolved!=null ? Variant.From(resolved) : default,new Settings(),0,revisions),climate!=null && climate.HasMethod("signature") ? climate.Call("signature") : 0});
    }
    public Godot.Environment? world_environment(Resource document)
    {
        var resource=Resolve(document.Get("atmosphere").As<Resource>()); string path=document.Get("environment_source").AsString();
        if(path.Length>0 && ResourceLoader.Exists(path)) resource=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Replace);
        if(resource is Godot.Environment environment)
        {
            if(environment.Sky?.SkyMaterial is ShaderMaterial authored)
            {
                var material=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("timeline_material",authored,false).As<Material>();
                if(material!=authored) {var copy=(Godot.Environment)environment.Duplicate(); using var sky=(Sky)environment.Sky.Duplicate(); copy.Sky=sky; sky.SkyMaterial=material; return copy;}
            }
            return environment;
        }
        if(resource!=null && ScriptType(resource,"res://scripts/actors/core/actor_object_data.gd") && resource.Get("type_id").AsString()=="environment")
        {
            var result=new Godot.Environment(); var adapter=new BasicActorRuntime();
            try {adapter.Call("_configure_environment",result,resource);} finally {adapter.Free();} return result;
        }
        return null;
    }
}
