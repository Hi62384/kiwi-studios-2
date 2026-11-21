using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ActorDefinitionOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorPropertyOperations _properties=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Resource? find_property(Resource definition,StringName key){foreach(var value in definition.Get("properties").AsGodotArray()){var property=value.As<Resource>();if(property!=null&&property.Get("id").AsStringName()==key)return property;}return null;}
    public Resource create_actor(Resource definition,Settings initial)
    {
        var actor=new ActorData();actor.Set("id",_data.new_id());actor.Set("type_id",definition.Get("type_id"));actor.Set("display_name",definition.Get("display_name"));actor.Set("schema_version",definition.Get("schema_version"));var values=actor.Get("values").AsGodotDictionary();var properties=definition.Get("properties").AsGodotArray();foreach(var value in properties){var property=value.As<Resource>();values[property.Get("id")]=_properties.create_default(property);}foreach(var value in properties){var property=value.As<Resource>();var key=property.Get("id");if(initial.TryGetValue(key,out var configured)&&_properties.accepts(property,configured))values[key]=_data.copy_value(configured);}foreach(var value in properties){var property=value.As<Resource>();var key=property.Get("id");if(!initial.ContainsKey(key))values[key]=_properties.create_default_for_actor(property,actor);}return actor;
    }
    public bool set_actor_property(Resource definition,Resource actor,StringName key,Variant value){var property=find_property(definition,key);if(actor.Get("type_id").AsString()!=definition.Get("type_id").AsString()||property==null||!_properties.accepts(property,value))return false;_data.set_value(actor,key,value);return true;}
    public Node? create_runtime(Resource definition,Resource actor)
    {
        var scene=definition.Get("runtime_scene").As<PackedScene>();if(scene==null||actor.Get("type_id").AsString()!=definition.Get("type_id").AsString())return null;var instance=scene.Instantiate();if(instance is not ActorRuntime){instance.Free();GD.PushError("Actor runtime scene root must extend ActorRuntime: "+definition.Get("type_id").AsString());return null;}instance.Call("bind",actor);return instance;
    }
    public Variant value_for(Resource? resource,Resource property){if(resource!=null&&resource.Get("values").AsGodotDictionary().TryGetValue(property.Get("id"),out var value)&&_properties.accepts(property,value))return value;return _properties.create_default(property);}
    public Resource create_object(Resource definition){var resource=new ActorObjectData();resource.Set("type_id",definition.Get("type_id"));resource.Set("schema_version",definition.Get("schema_version"));var values=resource.Get("values").AsGodotDictionary();foreach(var value in definition.Get("properties").AsGodotArray()){var property=value.As<Resource>();values[property.Get("id")]=_properties.create_default(property);}if(values.TryGetValue(new StringName("material_id"),out var id)&&id.ToString().Length==0)values[new StringName("material_id")]=_data.new_id();return resource;}
    public bool set_object_property(Resource definition,Resource resource,StringName key,Variant value){if(resource.Get("type_id").AsString()!=definition.Get("type_id").AsString())return false;var property=find_property(definition,key);if(property==null||!_properties.accepts(property,value))return false;_data.set_value(resource,key,value);return true;}
    public bool register(RefCounted registry,Resource? definition)
    {
        if(definition==null)return false;var definitions=registry.Get("_definitions").AsGodotDictionary();var type=definition.Get("type_id");if(type.AsString().Length==0||definitions.ContainsKey(type))return false;var ids=new Settings();foreach(var value in definition.Get("properties").AsGodotArray()){var property=value.As<Resource>();if(property==null)return false;var id=property.Get("id");if(id.AsString().Length==0||ids.ContainsKey(id)||!_properties.accepts(property,Get(property.Get("options").AsGodotDictionary(),"default")))return false;ids[id]=true;}definitions[type]=definition;return true;
    }
    public Resource? get_definition(RefCounted registry,StringName type){var definitions=registry.Get("_definitions").AsGodotDictionary();return definitions.TryGetValue(type,out var definition)?definition.As<Resource>():null;}
    public GArray get_definitions(RefCounted registry){var result=new GArray();foreach(var value in registry.Get("_definitions").AsGodotDictionary().Values)result.Add(value);return result;}
    public bool register_object(RefCounted registry,Resource? definition){if(definition==null)return false;var definitions=registry.Get("_object_definitions").AsGodotDictionary();var type=definition.Get("type_id");if(type.AsString().Length==0||definitions.ContainsKey(type))return false;definitions[type]=definition;return true;}
    public Resource? get_object_definition(RefCounted registry,StringName type){var definitions=registry.Get("_object_definitions").AsGodotDictionary();return definitions.TryGetValue(type,out var definition)?definition.As<Resource>():null;}
    public GArray object_definitions_for(RefCounted registry,StringName baseType)
    {
        var result=new List<Resource>();foreach(var value in registry.Get("_object_definitions").AsGodotDictionary().Values){var definition=value.As<Resource>();if(definition.Get("type_id").AsStringName()==baseType||definition.Get("base_type").AsStringName()==baseType)result.Add(definition);}using var compare=new Expression();compare.Parse("a.naturalnocasecmp_to(b)",new[]{"a","b"});result.Sort((a,b)=>a==b?0:a.Get("type_id").AsStringName()==baseType?-1:b.Get("type_id").AsStringName()==baseType?1:compare.Execute(new GArray{a.Get("display_name"),b.Get("display_name")}).AsInt32());var output=new GArray();foreach(var definition in result)output.Add(definition);return output;
    }
    public bool object_type_matches(RefCounted registry,StringName type,StringName baseType){var definition=get_object_definition(registry,type);return type==baseType||definition!=null&&definition.Get("base_type").AsStringName()==baseType;}
}
