using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ModelReferenceRemap : RefCounted
{
    private static Variant Value(Settings source,Variant key,Variant fallback)=>source.TryGetValue(key,out var value)?value:fallback;
    private static string Text(Variant value)=>value.VariantType==Variant.Type.Nil?"":value.AsString();
    private static Variant Mapped(Settings mapping,string key,Variant fallback)=>mapping.TryGetValue(key,out var value)?value:fallback;
    public void _structure(Settings settings,Settings mapping)
    {
        if(settings.TryGetValue(new StringName("structure_connections"),out var connections))foreach(var pair in connections.AsGodotDictionary()){var link=pair.Value.AsGodotDictionary();link["target"]=Mapped(mapping,Text(Value(link,"target","")),"");}
        var assembly=new StringName("structure_assembly");if(settings.TryGetValue(assembly,out var id))settings[assembly]=Mapped(mapping,Text(id),id);
    }
    public void component(Resource item,Settings mapping)
    {
        var parameters=item.Get("parameters").AsGodotDictionary();var originalParameters=parameters.Duplicate(true);originalParameters.Remove("_module_bindings");
        if(parameters.TryGetValue("_module_bindings",out var modules)&&modules.VariantType==Variant.Type.Dictionary)
        {
            var remapped=new Settings();foreach(var pair in modules.AsGodotDictionary())
            {string owner=Text(pair.Key);if(!mapping.TryGetValue(owner,out var mapped))continue;var binding=pair.Value.AsGodotDictionary().Duplicate(true);var parent=Value(binding,"parent","");binding["parent"]=Mapped(mapping,Text(parent),parent);remapped[mapped]=binding;}
            parameters["_module_bindings"]=remapped;
        }
        string skeleton=item.Get("skeleton_id").AsString();item.Set("skeleton_id",Mapped(mapping,skeleton,skeleton));var growth=item.Get("growth").As<Resource>();if(growth!=null){var id=growth.Get("source_id");growth.Set("source_id",Mapped(mapping,Text(id),id));}
        var structural=item.Get("structural").AsGodotDictionary();_structure(structural,mapping);
        if(parameters.TryGetValue("_architecture_structure",out var structure)&&structure.VariantType==Variant.Type.Dictionary)_structure(structure.AsGodotDictionary(),mapping);
        string itemId=item.Get("id").AsString();
        if(parameters.TryGetValue("architecture_owner",out var architectureOwner))
        {
            string owner=Text(architectureOwner);if(mapping.TryGetValue(owner,out var mapped))parameters["architecture_owner"]=mapped;
            else if(parameters.ContainsKey("architecture_key")){foreach(string key in new[]{"architecture_key","architecture_owner","architecture_material_slot","architecture_material_slots"})parameters.Remove(key);if(structural.ContainsKey(new StringName("structure_assembly")))structural[new StringName("structure_assembly")]=itemId;}
        }
        if(parameters.TryGetValue("architecture_source",out var source)&&source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Resource architecture&&architecture.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs")
        {var copy=BuildingSource.copy(architecture);copy.Set("source_id",itemId);parameters["architecture_source"]=copy;}
        if(parameters.TryGetValue("world_source",out var worldValue)&&worldValue.VariantType==Variant.Type.Object&&worldValue.AsGodotObject() is Resource world&&world.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs")
        {
            var copy=world.Call("copy").As<Resource>();string previous=copy.Get("world_id").AsString();copy.Set("world_id",itemId);copy.Set("terrain_id",Mapped(mapping,Text(copy.Get("terrain_id")),copy.Get("terrain_id")));copy.Set("owned_terrain_id",Mapped(mapping,Text(copy.Get("owned_terrain_id")),""));
            foreach(Variant value in copy.Get("regions").AsGodotArray()){var region=value.AsGodotDictionary();region["id"]=Text(region["id"]).Replace(previous+":region:",itemId+":region:",StringComparison.Ordinal);}parameters["world_source"]=copy;
        }
        if(parameters.TryGetValue("world_owner",out var worldOwner))
        {
            string owner=Text(worldOwner);
            if(mapping.TryGetValue(owner,out var mapped))
            {parameters["world_owner"]=mapped;if(parameters.TryGetValue("world_parent",out var parent))parameters["world_parent"]=Mapped(mapping,Text(parent),parent);if(parameters.TryGetValue("world_region",out var region))parameters["world_region"]=Text(region).Replace(owner+":region:",Text(mapped)+":region:",StringComparison.Ordinal);}
            else foreach(string key in new[]{"world_owner","world_generated","world_key","world_mesh_key","world_mesh_version","world_global_pose","world_parent","world_manual_parent","world_generated_visible"})parameters.Remove(key);
        }
        if(parameters.TryGetValue("_module_bindings",out var bindings))foreach(var pair in bindings.AsGodotDictionary())
        {
            var binding=pair.Value.AsGodotDictionary();_structure(Value(binding,"structure",new Settings()).AsGodotDictionary(),mapping);var baselineParameters=Value(binding,"parameters",new Settings()).AsGodotDictionary();
            if(baselineParameters.RecursiveEqual(originalParameters)){var current=parameters.Duplicate(true);current.Remove("_module_bindings");binding["parameters"]=current;}
            else {using var baseline=new KiwiModelComponent();baseline.Set("id",itemId);baseline.Set("parameters",baselineParameters.Duplicate(true));component(baseline,mapping);binding["parameters"]=baseline.Get("parameters");}
        }
    }
    public void terrain(Resource? source,Settings mapping)
    {
        if(source==null)return;
        foreach(Variant value in source.Get("caves").AsGodotArray())
        {var cave=value.As<Resource>();if(!cave.HasMeta("world_road_owner"))continue;string owner=Text(cave.GetMeta("world_road_owner"));if(mapping.TryGetValue(owner,out var mapped)){cave.SetMeta("world_road_owner",mapped);cave.Set("cave_id",cave.Get("cave_id").AsString().Replace(owner+":tunnel:",Text(mapped)+":tunnel:",StringComparison.Ordinal));}else cave.RemoveMeta("world_road_owner");}
        var generation=source.Get("generation").As<Resource>();if(generation==null)return;
        foreach(Variant value in generation.Get("layers").AsGodotArray())
        {
            var layer=value.AsGodotDictionary();if(Text(Value(layer,"type",""))=="Foundation"&&mapping.TryGetValue(Text(Value(layer,"foundation_owner","")),out var owner)){layer["foundation_owner"]=owner;layer["id"]="foundation:"+Text(owner);}
            if(mapping.TryGetValue(Text(Value(layer,"world_road_owner","")),out var road))layer["world_road_owner"]=road;
        }
    }
}
