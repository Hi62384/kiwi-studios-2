using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentActorOperations
{
    private static string Normalize(string path)=>ProjectSettings.GlobalizePath(path).Replace('\\','/').SimplifyPath();
    public void load_source(Node3D owner,string path)
    {
        cancel_source_jobs(owner);owner.Set("source_path",path);owner.Set("error", "");owner.Set("linked_source_warning", "");owner.Set("source_document",default(Variant));Resource? source=null;if(path.Length>0&&ResourceLoader.Exists(path)){var loaded=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Replace);if(loaded!=null&&Type(loaded,"res://Workspaces/EnvironmentWorkspace/environment_document.gd"))source=loaded;}if(source==null){owner.Set("error","Choose a saved Environment document.");clear_source(owner);return;}owner.Set("source_document",source);var errors=_documents.validate(source);if(errors.Length>0){owner.Set("error",errors[0]);clear_source(owner);return;}var resolved=_links.resolve(source);if(resolved["document"].As<Resource>() is Resource document)owner.Set("source_document",document);else owner.Set("linked_source_warning",resolved["error"].AsString()+" Saved instance geometry is retained.");prepare_source(owner);
    }
    public void prepare_source(Node3D owner)
    {
        cancel_source_jobs(owner);var source=Document(owner)!;var pending=new List<string>();foreach(var value in source.Get("components").AsGodotArray()){var item=value.As<Resource>();string id=item.Get("id").AsString();var terrain=_documents.terrain(source,id);if(terrain!=null&&(terrain.Get("resolution").AsInt32()>257||!terrain.Call("water_valid").AsBool()||!terrain.Call("biomes_valid").AsBool()||!terrain.Call("volumes_valid").AsBool()||!terrain.Call("cave_biomes_valid").AsBool()))pending.Add(id);}if(pending.Count==0){configure_source(owner);return;}source=_documents.snapshot(source);owner.Set("source_document",source);clear_source(owner);owner.Set("error","Preparing environment terrain…");foreach(string id in pending){var job=new EnvironmentGenerationJob();Jobs(owner).Add(new Settings {["id"]=id,["generation"]=owner.Get("_source_generation"),["job"]=job});job.start(_documents.terrain(source,id)!,new Settings(),false);}
    }
    public void configure_source(Node3D owner)
    {
        var source=Document(owner)!;long chunks=0;var components=source.Get("components").AsGodotArray();foreach(var value in components){var terrain=_documents.terrain(source,value.As<Resource>().Get("id").AsString());if(terrain!=null){long side=(long)Math.Ceiling((terrain.Get("resolution").AsDouble()-1)/32);chunks+=side*side;}}var content=Content(owner)!;content.Set("progressive",chunks>64||components.Count>64);content.Set("upload_budget_usec",8000);var camera=owner.GetViewport().GetCamera3D();content.Set("priority_camera",camera!=null?Variant.From(camera):default);_runtime.configure(content,source);set_timeline_time(owner,owner.Get("shader_time").AsDouble());string warning=owner.Get("linked_source_warning").AsString();if(warning.Length>0){var errors=content.Get("errors").AsStringArray().ToList();errors.Add(warning);content.Set("errors",errors.ToArray());}
    }
    public void clear_source(Node3D owner)
    {var empty=new KiwiEnvironmentDocument();empty.Set("sunlight",new Settings {["enabled"]=false});_runtime.configure(Content(owner)!,empty);}
    public void reload_environment(Node3D owner,string path)
    {if(Normalize(path)!=Normalize(owner.Get("source_path").AsString()))return;var source=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Replace);if(source!=null&&Type(source,"res://Workspaces/EnvironmentWorkspace/environment_document.gd")){owner.Set("source_document",source);prepare_source(owner);}else owner.Set("source_document",default(Variant));}
    public void refresh_saved_model(Node3D owner,string path)
    {
        var source=Document(owner);if(source==null)return;Assets().Call("invalidate",path);if(!_documents.references_asset(source,path))return;var linked=_links.resolve(source);if(linked["document"].As<Resource>() is Resource resolved){source=resolved;owner.Set("source_document",source);owner.Set("linked_source_warning", "");}else owner.Set("linked_source_warning",linked["error"].AsString()+" Saved instance geometry is retained.");foreach(var value in source.Get("component_settings").AsGodotDictionary().Values){var metadata=value.AsGodotDictionary();var sources=new List<string>{Get(metadata,"source", "").AsString()};var scatter=Get(metadata,"scatter").As<Resource>();if(scatter!=null)foreach(var entry in scatter.Get("palette").AsGodotArray())sources.Add(Get(entry.AsGodotDictionary(),"source", "").AsString());foreach(string dependency in sources)if(dependency.Length>0&&_documents.references(dependency,Normalize(path),new Settings(),0))Assets().Call("invalidate",dependency);}configure_source(owner);
    }
    public void refresh_saved_image(Node3D owner,Variant source)
    {string path=source.VariantType==Variant.Type.String?source.AsString():source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Resource resource?resource.ResourcePath:"";if(path.Length>0)refresh_saved_model(owner,path);}
    public void set_timeline_time(Node3D owner,double time)
    {
        owner.Set("shader_time",time);var content=Content(owner)!;content.Set("preview_time",time);var visited=new HashSet<ulong>();foreach(var visual in content.FindChildren("*","GeometryInstance3D",true,false).OfType<GeometryInstance3D>())
        {
            Mesh? mesh=visual is MeshInstance3D instance?instance.Mesh:visual is MultiMeshInstance3D repeated?repeated.Multimesh?.Mesh:null;var materials=new List<Material>();if(visual.MaterialOverride!=null)materials.Add(visual.MaterialOverride);if(mesh!=null)for(int surface=0;surface<mesh.GetSurfaceCount();surface++){var material=visual is MeshInstance3D actual?actual.GetActiveMaterial(surface):mesh.SurfaceGetMaterial(surface);if(material!=null)materials.Add(material);}foreach(var material in materials){if(material is not ShaderMaterial shader||!visited.Add(material.GetInstanceId()))continue;shader.SetMeta("kiwi_last_time",time);if(shader.HasMeta("kiwi_timeline_link"))shader.GetMeta("kiwi_timeline_link").As<GodotObject>()?.Call("synchronize_parameters");string uniform=shader.GetMeta("kiwi_time_uniform", "").AsString();if(uniform.Length>0)shader.SetShaderParameter(uniform,time);}
        }
    }
}
