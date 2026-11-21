using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModuleLinkOperations
{
    private static Settings Bindings(Resource item)=>Get(Values(item),"_module_bindings",new Settings()).AsGodotDictionary();
    private static long BindingSignature(Resource? binding)=>binding!=null?binding.Call("signature").AsInt64():0;
    private static bool ArrayEqual(Variant a,Variant b)=>a.AsGodotArray().RecursiveEqual(b.AsGodotArray());
    private static bool DictionaryEqual(Variant a,Variant b)=>a.AsGodotDictionary().RecursiveEqual(b.AsGodotDictionary());
    public string replace(Resource document,string id,Resource source,bool reset)
    {
        var lookup=ModelDocumentOperations.Lookup(document);if(!lookup.TryGetValue(id,out var group))return "The linked instance no longer exists.";var old=new Dictionary<string,Resource>();var oldIds=new HashSet<string>();foreach(var item in lookup.Values){var bindings=Bindings(item);if(bindings.TryGetValue(id,out var baseline)){old[baseline.AsGodotDictionary()["source"].AsString()]=item;oldIds.Add(Text(item,"id"));}}if(old.Count==0)return "This older snapshot has no source bindings. Insert a fresh linked instance; its existing edits are preserved.";
        if(reset){var proceduralOwners=new HashSet<string>(old.Values.Where(c=>Values(c).ContainsKey("architecture_source")).Select(c=>Text(c,"id")));foreach(var item in lookup.Values)if(Values(item).ContainsKey("architecture_key")&&proceduralOwners.Contains(Get(Values(item),"architecture_owner", "").AsString()))oldIds.Add(Text(item,"id"));}
        var mapping=new Settings();var parts=new List<Resource>();var live=new HashSet<string>();var changedSurfaces=new HashSet<string>();var changedRigs=new HashSet<string>();var originals=Components(source);foreach(var original in originals)mapping[Text(original,"id")]=old.TryGetValue(Text(original,"id"),out var prior)?Text(prior,"id"):Guid.NewGuid().ToString("N");
        foreach(var original in originals)
        {
            if(!old.TryGetValue(Text(original,"id"),out var previous))continue;var baseline=Bindings(previous)[id].AsGodotDictionary();if(_geometry.mesh_key(original.Get("mesh").As<Resource>(),2)!=baseline["mesh"].AsInt64())changedSurfaces.Add(Text(previous,"id"));if(original.Get("is_skeleton").AsBool()&&_rig.bind_signature(original.Get("bones").AsGodotArray())!=Get(baseline,"rig_rest",0).AsInt64())changedRigs.Add(Text(previous,"id"));
        }
        foreach(var original in originals)
        {
            var item=_components.copy_component(original,false);item.Set("id",mapping[original.Get("id")]);item.Set("parent_id",Get(mapping,Text(original,"parent_id"),id));_references.component(item,mapping);bind(item,id,Text(original,"id"));
            if(old.TryGetValue(Text(original,"id"),out var previous))
            {
                var before=Bindings(previous)[id].AsGodotDictionary();var fresh=Bindings(item)[id].AsGodotDictionary();bool manualParameters=Get(before,"manual_parameters",false).AsBool()||!parameters(previous).RecursiveEqual(before["parameters"].AsGodotDictionary());if(!reset&&manualParameters&&Values(previous).ContainsKey("architecture_source"))return "This linked procedural building has local source edits. Make it unique or reset its source overrides before updating.";if(!reset&&manualParameters&&before["parameters"].AsGodotDictionary().ContainsKey("architecture_module_source"))return "A nested linked source has local edits. Make the outer instance unique or reset source overrides before updating.";var bindings=reset?new Settings():Bindings(previous).Duplicate(true);foreach(var pair in Bindings(item))bindings[pair.Key]=pair.Value;Values(item)["_module_bindings"]=bindings;fresh=bindings[id].AsGodotDictionary();
                if(!reset)
                {
                    if(!ArrayEqual(previous.Get("bones"),Get(before,"bones",new GArray()))||Get(before,"manual_bones",false).AsBool()){if(changedRigs.Contains(Text(previous,"id")))return "Local rig edits conflict with changed source rest bones. Make unique or reset source overrides.";item.Set("bones",previous.Get("bones").AsGodotArray().Duplicate(true));fresh["manual_bones"]=true;}
                    var previousBinding=previous.Get("binding").As<Resource>();if(BindingSignature(previousBinding)!=Get(before,"binding",0).AsInt64()||Get(before,"manual_binding",false).AsBool()){if(changedRigs.Contains(Text(previous,"skeleton_id")))return "Local skin weights require an explicit rebind after source rest-bone changes.";item.Set("binding",previousBinding!=null?previousBinding.Call("copy_binding"):default);foreach(string key in new[]{"skin","skin_mesh","mesh"})item.Set(key,previous.Get(key));fresh["manual_binding"]=true;}
                    var growth=previous.Get("growth").As<Resource>();if(growth_key(growth)!=Get(before,"growth",0).AsInt64()||Get(before,"manual_growth",false).AsBool()){if(growth!=null&&changedSurfaces.Contains(Text(growth,"source_id")))return "Local grooming needs a surface rebind before updating changed source geometry. Make unique or reset source overrides.";item.Set("growth",growth!=null?growth.Call("copy_data"):default);fresh["manual_growth"]=true;}
                    if(Get(before,"manual_pose",false).AsBool()||previous.Get("transform").AsTransform3D()!=before["pose"].AsTransform3D()){item.Set("transform",previous.Get("transform"));fresh["manual_pose"]=true;}
                    if(Get(before,"manual_parent",false).AsBool()||Text(previous,"parent_id")!=before["parent"].AsString()){item.Set("parent_id",previous.Get("parent_id"));fresh["manual_parent"]=true;}
                    if(Get(before,"manual_mesh",false).AsBool()||_geometry.mesh_key(previous.Get("mesh").As<Resource>(),2)!=before["mesh"].AsInt64()){foreach(string key in new[]{"mesh","geometry_source","geometry_source_hash","skin","skin_mesh"})item.Set(key,previous.Get(key));item.Set("binding",previousBinding!=null?previousBinding.Call("copy_binding"):default);fresh["manual_mesh"]=true;}
                    if(Get(before,"manual_material",false).AsBool()||!ArrayEqual(previous.Get("surface_materials"),before["materials"])){item.Set("surface_materials",previous.Get("surface_materials"));fresh["manual_material"]=true;}
                    if(Get(before,"manual_modifiers",false).AsBool()||!ArrayEqual(previous.Get("modifiers"),before["modifiers"])){item.Set("modifiers",previous.Get("modifiers").AsGodotArray().Duplicate(true));fresh["manual_modifiers"]=true;}
                    if(manualParameters){var retained=Values(previous).Duplicate(true);retained["_module_bindings"]=bindings;item.Set("parameters",retained);item.Set("generator",previous.Get("generator"));fresh["manual_parameters"]=true;}
                    if(Text(previous,"title")!=before["name"].AsString()||Get(before,"manual_name",false).AsBool()){item.Set("title",previous.Get("title"));fresh["manual_name"]=true;}
                    if(!DictionaryEqual(previous.Get("structural"),before["structure"])||Get(before,"manual_structure",false).AsBool()){item.Set("structural",previous.Get("structural").AsGodotDictionary().Duplicate(true));fresh["manual_structure"]=true;}
                    if(previous.Get("visible").AsBool()!=before["visible"].AsBool()||Get(before,"manual_visible",false).AsBool()){item.Set("visible",previous.Get("visible"));fresh["manual_visible"]=true;}
                    if(previous.Get("locked").AsBool()!=before["locked"].AsBool()||Get(before,"manual_locked",false).AsBool()){item.Set("locked",previous.Get("locked"));fresh["manual_locked"]=true;}
                }
            }
            live.Add(Text(item,"id"));parts.Add(item);
        }
        var extraPoses=new Dictionary<string,Transform3D>();foreach(var item in lookup.Values)if(!oldIds.Contains(Text(item,"id"))&&oldIds.Contains(Text(item,"parent_id"))&&!live.Contains(Text(item,"parent_id")))extraPoses[Text(item,"id")]=ModelDocumentOperations.WorldTransform(lookup,item);var inverse=ModelDocumentOperations.WorldTransform(lookup,group).AffineInverse();foreach(var item in parts)if(oldIds.Contains(Text(item,"parent_id"))&&!live.Contains(Text(item,"parent_id"))){string sourceId=Bindings(item)[id].AsGodotDictionary()["source"].AsString();item.Set("transform",inverse*ModelDocumentOperations.WorldTransform(lookup,old[sourceId]));item.Set("parent_id",id);}var components=document.Get("components").AsGodotArray();for(int index=components.Count-1;index>=0;index--)if(oldIds.Contains(Text(components[index].As<Resource>(),"id")))components.RemoveAt(index);foreach(var item in parts)components.Add(item);var replacedLookup=ModelDocumentOperations.Lookup(document);foreach(var entry in extraPoses)if(replacedLookup.TryGetValue(entry.Key,out var child)){child.Set("parent_id",id);child.Set("transform",inverse*entry.Value);}if(Environment(document)){var settings=document.Get("component_settings").AsGodotDictionary();foreach(string removed in oldIds)if(!live.Contains(removed))settings.Remove(removed);foreach(var item in parts)settings[Text(item,"id")]=new Settings {["kind"]="asset",["collision"]=item.Get("mesh").As<Resource>()!=null};}return "";
    }
}
