using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingSessionOperations : RefCounted
{
    private readonly BuildingSourceOperations _sources=new();
    private readonly BuildingGeometryOperations _builder=new();
    private readonly ModelDocumentOperations _documents=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static string Text(Resource item,string name)=>item.Get(name).AsString();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static bool ScriptType(Resource item,string path)
    {var script=item.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private static bool Environment(Resource document)=>ScriptType(document,"res://Workspaces/EnvironmentWorkspace/environment_document.gd");
    private static void Action(RefCounted session,string label,Action operation){session.Call("begin");operation();session.Call("commit",label);}
    public Resource? source(Resource? item)
    {if(item==null)return null;var value=Get(item.Get("parameters").AsGodotDictionary(),"architecture_source");if(value.VariantType!=Variant.Type.Object)return null;var resource=value.As<Resource>();return resource?.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs"?resource:null;}
    public Resource? owner(RefCounted session,Resource? item)
    {var document=Document(session);var lookup=ModelDocumentOperations.Lookup(document);var visited=new HashSet<string>();while(item!=null&&visited.Add(Text(item,"id"))){if(source(item)!=null)return item;lookup.TryGetValue(Text(item,"parent_id"),out item);}return null;}
    public long source_key(Resource value)
    {using var fields=new GArray();foreach(string key in new[]{"title","seed","footprint","floors","wall_thickness","slab_thickness","roof_type","roof_pitch","roof_overhang","materials","stairs","physics_enabled","foundation_depth","style","facade_detail","detail_width","baseboard_height","crown_height","interior_trim_depth"})fields.Add(value.Get(key));return unchecked((uint)GD.Hash(fields));}
    public void mark(Resource item)
    {var values=item.Get("parameters").AsGodotDictionary();values["_architecture_pose"]=item.Get("transform");values["_architecture_mesh"]=_builder.mesh_key(item.Get("mesh").As<Resource>(),2);values["_architecture_mesh_format"]=2;values["_architecture_materials"]=item.Get("surface_materials").AsGodotArray().Duplicate();values["_architecture_structure"]=item.Get("structural").AsGodotDictionary().Duplicate(true);}
    public void environment_settings(RefCounted session,Resource item)
    {var document=Document(session);if(Environment(document))document.Get("component_settings").AsGodotDictionary()[Text(item,"id")]=new Settings {["kind"]="asset",["collision"]=true};}
    public Resource? add(RefCounted session,Vector3 position,int levels)
    {
        var authored=_sources.rectangular(6,8,levels,true);var generated=_builder.Generate(authored,()=>false);var model=generated["document"].As<Resource>();if(model==null)return null;var components=model.Get("components").AsGodotArray();var root=components[0].As<Resource>();var pose=root.Get("transform").AsTransform3D();pose.Origin=position;root.Set("transform",pose);Action(session,"Add building",()=>{foreach(var value in components){var component=value.As<Resource>();mark(component);Document(session).Get("components").AsGodotArray().Add(component);environment_settings(session,component);}var selected=session.Get("selected").AsGodotArray();selected.Clear();selected.Add(Text(root,"id"));});return root;
    }
    public Settings reset_overrides(RefCounted session,string id,string componentId)
    {
        var document=Document(session);var item=_documents.component(document,componentId);var root=_documents.component(document,id);if(item==null||root==null)return new Settings {["errors"]=new[]{"The component no longer exists."},["warnings"]=Array.Empty<string>()};session.Call("begin");var values=item.Get("parameters").AsGodotDictionary();foreach(string key in new[]{"_architecture_manual","_architecture_manual_pose","_architecture_manual_material","_architecture_manual_structure"})values[key]=false;mark(item);item.Set("pivot",Vector3.Zero);var result=update(session,id,source(root)!,"Reset building component overrides",true,true,new Settings());if(result["errors"].AsStringArray().Length>0)session.Call("cancel");else session.Call("commit","Reset building component overrides");return result;
    }
}
