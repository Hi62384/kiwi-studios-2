using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModuleLinkOperations : RefCounted
{
    private readonly ModelDocumentOperations _documents=new();
    private readonly ModelComponentOperations _components=new();
    private readonly ModelReferenceRemap _references=new();
    private readonly BuildingGeometryOperations _geometry=new();
    private readonly RigMath _rig=new();
    private readonly EnvironmentDataHash _hash=new();
    private static ModelSourceLink Files()=>Engine.GetSingleton("KiwiNativeServices").Call("service","model_source_link").As<ModelSourceLink>();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static string Text(Resource value,string key)=>value.Get(key).AsString();
    private static Settings Values(Resource component)=>component.Get("parameters").AsGodotDictionary();
    private static Resource[] Components(Resource document)=>document.Get("components").AsGodotArray().Select(v=>v.As<Resource>()).ToArray();
    private static bool ScriptType(Resource value,string path)
    {var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private static bool Model(Resource value)=>ScriptType(value,"res://Workspaces/ModelWorkspace/model_document.gd");
    private static bool Environment(Resource value)=>ScriptType(value,"res://Workspaces/EnvironmentWorkspace/environment_document.gd");
    private static Settings Failure(string error)=>new() {["document"]=default,["error"]=error};
    public Settings parameters(Resource item){var result=Values(item).Duplicate(true);result.Remove("_module_bindings");return result;}
    public long growth_key(Resource? growth)
    {
        if(growth==null)return 0;var appearance=growth.Get("appearance").As<Resource>();var style=growth.Get("growth_style").As<Resource>();using var values=new GArray();foreach(string key in new[]{"settings","faces","groom","groom_layers","guides","protected_faces"})values.Add(growth.Get(key));values.Add(appearance!=null?appearance.Call("signature"):Variant.From(0));values.Add(style!=null?style.Get("values"):Variant.From(new Settings()));foreach(string key in new[]{"rendering","regions","individual"})values.Add(growth.Get(key));return _hash.value(values);
    }
    public void bind(Resource item,string owner,string sourceId)
    {
        var values=Values(item);var bindings=Get(values,"_module_bindings",new Settings()).AsGodotDictionary().Duplicate(true);var binding=item.Get("binding").As<Resource>();bindings[owner]=new Settings {["source"]=sourceId,["pose"]=item.Get("transform"),["parent"]=item.Get("parent_id"),["mesh"]=_geometry.mesh_key(item.Get("mesh").As<Resource>(),2),["materials"]=item.Get("surface_materials").AsGodotArray().Duplicate(),["modifiers"]=item.Get("modifiers").AsGodotArray().Duplicate(true),["parameters"]=parameters(item),["generator"]=item.Get("generator"),["name"]=item.Get("title"),["visible"]=item.Get("visible"),["locked"]=item.Get("locked"),["structure"]=item.Get("structural").AsGodotDictionary().Duplicate(true),["bones"]=item.Get("bones").AsGodotArray().Duplicate(true),["rig_rest"]=item.Get("is_skeleton").AsBool()?_rig.bind_signature(item.Get("bones").AsGodotArray()):0,["binding"]=binding!=null?binding.Call("signature"):Variant.From(0),["growth"]=growth_key(item.Get("growth").As<Resource>())};values["_module_bindings"]=bindings;
    }
    public Settings load(string path,string[] chain,Settings cache)
    {
        if(path.Length==0)return Failure("The linked source path is empty.");path=Files()._path(path);if(chain.Contains(path)||chain.Length>=16)return Failure("Linked model sources contain a cycle or exceed sixteen levels.");if(cache.TryGetValue(path,out var cached))return new Settings {["document"]=cached,["error"]=""};var source=Files().load_resource(path);if(source==null||!Model(source)||Environment(source))return Failure("A linked source must be an editable native Model resource: "+path.GetFile());var document=_documents.snapshot(source);var next=chain.Append(path).ToArray();var roots=Components(document).Where(c=>Get(Values(c),"module_linked",false).AsBool()).Select(c=>Text(c,"id")).ToArray();foreach(string id in roots){var group=_documents.component(document,id);if(group==null)continue;var loaded=load(Get(Values(group),"architecture_module_source", "").AsString(),next,cache);var child=loaded["document"].As<Resource>();if(child==null)return loaded;string error=replace(document,id,child,false);if(error.Length>0)return Failure(error);}cache[path]=document;return new Settings {["document"]=document,["error"]=""};
    }
    public bool depends_on(string path,string target)=>depends_on_visited(path,target,new Settings());
    public bool depends_on_visited(string path,string target,Settings visited)
    {
        path=Files()._path(path);target=Files()._path(target);if(path==target)return true;if(visited.ContainsKey(path))return false;if(visited.Count>=64)return true;visited[path]=true;var document=Files().load_resource(path);if(document==null||!Model(document))return false;foreach(var component in Components(document))if(Get(Values(component),"module_linked",false).AsBool()&&depends_on_visited(Get(Values(component),"architecture_module_source", "").AsString(),target,visited))return true;return false;
    }
}
