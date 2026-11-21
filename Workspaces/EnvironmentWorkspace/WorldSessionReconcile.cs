using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSessionOperations
{
    private static Settings Parameters(Resource item)=>item.Get("parameters").AsGodotDictionary();
    private static bool ArraysEqual(GArray a,GArray b)=>a.RecursiveEqual(b);
    private static bool HasObject(Resource item,string key)=>item.Get(key).AsGodotObject()!=null;
    private static bool Generated(Resource item,string owner)=>Get(Parameters(item),"world_generated",false).AsBool()&&Get(Parameters(item),"world_owner",item.Get("parent_id")).AsString()==owner;
    private static string TrimOwner(string id,string owner)=>id.StartsWith(owner,StringComparison.Ordinal)?id[owner.Length..]:id;
    private static Resource? Lookup(Settings values,string key)=>values.TryGetValue(key,out var value)?value.As<Resource>():null;
    private static Settings Failure(string text)=>new() {["errors"]=new[]{text},["warnings"]=Array.Empty<string>()};
    private string PreservePart(Resource part,Resource old,bool reused,WorldBuildingMassing stamp,BuildingSessionOperations architecture)
    {
        var previous=Parameters(old);var values=Parameters(part);part.Set("id",old.Get("id"));if(Get(previous,"world_manual_pose",false).AsBool()||old.Get("transform").AsTransform3D()!=Get(previous,"world_pose",Transform3D.Identity).AsTransform3D()){part.Set("transform",old.Get("transform"));values["world_manual_pose"]=true;}
        if(Get(previous,"world_manual_visible",false).AsBool()||old.Get("visible").AsBool()!=Get(previous,"world_generated_visible",true).AsBool()){part.Set("visible",old.Get("visible"));values["world_manual_visible"]=true;}part.Set("locked",old.Get("locked"));part.Set("title",old.Get("title"));part.Set("modifiers",old.Get("modifiers").AsGodotArray().Duplicate(true));if(!old.Get("structural").AsGodotDictionary().RecursiveEqual(Get(previous,"world_structure",new Settings()).AsGodotDictionary()))part.Set("structural",old.Get("structural").AsGodotDictionary().Duplicate(true));if(!ArraysEqual(old.Get("surface_materials").AsGodotArray(),Get(previous,"world_materials",old.Get("surface_materials")).AsGodotArray()))part.Set("surface_materials",old.Get("surface_materials").AsGodotArray().Duplicate());
        if(!reused&&previous.ContainsKey("architecture_source")&&previous.ContainsKey("world_architecture_source_key")&&architecture.source_key(previous["architecture_source"].As<Resource>())!=previous["world_architecture_source_key"].AsInt64())return "This building has local source edits. Keep it independent before regenerating its settlement.";
        int version=Get(previous,"world_mesh_version",1).AsInt32();var oldMesh=old.Get("mesh").As<Resource>();var newMesh=part.Get("mesh").As<Resource>();long key=stamp.stamp(oldMesh,2);bool shapeChanged=stamp.stamp(oldMesh,1)!=stamp.stamp(newMesh,1);if(shapeChanged&&(HasObject(old,"binding")||HasObject(old,"skin_mesh")||HasObject(old,"growth")))return "A rigged or groomed building needs an explicit rebind before its source geometry changes.";
        var binding=old.Get("binding").As<Resource>();part.Set("binding",binding!=null?binding.Call("copy_binding"):default);foreach(string field in new[]{"skin","skin_mesh","skeleton_id"})part.Set(field,old.Get(field));var growth=old.Get("growth").As<Resource>();part.Set("growth",growth!=null?growth.Call("copy_data"):default);
        bool manualMesh=stamp.stamp(oldMesh,version)!=Get(previous,"world_mesh_key",stamp.stamp(oldMesh,version)).AsInt64();if(version<2&&!shapeChanged&&key!=values["world_mesh_key"].AsInt64())manualMesh=true;
        if(manualMesh){part.Set("mesh",old.Get("mesh"));values["world_mesh_key"]=Get(previous,"world_mesh_key",key);values["world_mesh_version"]=version;}else if(key==values["world_mesh_key"].AsInt64())part.Set("mesh",old.Get("mesh"));return "";
    }
    private string RemovedConflict(Resource document,Settings existing,Settings replacement,WorldBuildingMassing stamp,BuildingSessionOperations architecture)
    {
        var protectedSources=new HashSet<string>();foreach(var value in document.Get("components").AsGodotArray()){var growth=value.As<Resource>().Get("growth").As<Resource>();if(growth!=null)protectedSources.Add(growth.Get("source_id").AsString());}
        foreach(var value in existing.Values)
        {
            var old=value.As<Resource>();string id=old.Get("id").AsString();if(replacement.ContainsKey(id))continue;var parameters=Parameters(old);string owner=Get(parameters,"architecture_owner","").AsString();if(parameters.ContainsKey("architecture_source"))owner=id;if(owner.Length==0&&!protectedSources.Contains(id))continue;int version=Get(parameters,"world_mesh_version",1).AsInt32();var mesh=old.Get("mesh").As<Resource>();
            bool edited=old.Get("transform").AsTransform3D()!=Get(parameters,"world_pose",old.Get("transform")).AsTransform3D()||!ArraysEqual(old.Get("surface_materials").AsGodotArray(),Get(parameters,"world_materials",old.Get("surface_materials")).AsGodotArray())||!old.Get("structural").AsGodotDictionary().RecursiveEqual(Get(parameters,"world_structure",old.Get("structural")).AsGodotDictionary())||old.Get("modifiers").AsGodotArray().Count>0||stamp.stamp(mesh,version)!=Get(parameters,"world_mesh_key",stamp.stamp(mesh,version)).AsInt64()||HasObject(old,"binding")||HasObject(old,"skin_mesh")||HasObject(old,"growth")||protectedSources.Contains(id);
            if(parameters.ContainsKey("architecture_source")&&parameters.ContainsKey("world_architecture_source_key"))edited|=architecture.source_key(parameters["architecture_source"].As<Resource>())!=parameters["world_architecture_source_key"].AsInt64();if(edited)return "This layout change would remove a customized or bound building component. Keep its building independent before regenerating.";
        }
        return "";
    }
}
