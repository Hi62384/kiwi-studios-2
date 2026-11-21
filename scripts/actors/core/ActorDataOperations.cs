using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ActorDataOperations:RefCounted
{
    private ActorAnimationOperations? _animation;
    internal static bool ScriptIs(Resource? value,string path){var script=value?.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private static Resource New(string file)=>file switch { "actor_data"=>new ActorData(), "actor_object_data"=>new ActorObjectData(), "actor_object_reference"=>new ActorObjectReference(), _=>throw new ArgumentException("Unknown actor data resource: "+file) };
    public string new_id(){using var crypto=new Crypto();return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant();}
    public Resource? animation_track(Resource actor,string[] path){foreach(var value in actor.Get("animation_tracks").AsGodotArray()){var track=value.As<Resource>();if(track.Get("path").AsStringArray().SequenceEqual(path))return track;}return null;}
    public void set_value(Resource resource,StringName key,Variant value){resource.Get("values").AsGodotDictionary()[key]=value;resource.EmitChanged();}
    public Variant object_get_value(Resource resource,StringName key,Variant fallback){var values=resource.Get("values").AsGodotDictionary();return values.TryGetValue(key,out var value)?value:fallback;}
    public Variant get_value(Resource actor,StringName key,Variant fallback)
    {
        var value=object_get_value(actor,key,fallback);string[] path={key.ToString()};var previews=actor.Get("animation_previews").AsGodotDictionary();if(previews.TryGetValue(string.Join(" / ",path),out var preview)&&preview.AsGodotDictionary().Count>0)return preview.AsGodotDictionary()["value"];double time=actor.Get("animation_time").AsDouble();return double.IsNaN(time)?value:(_animation??=new ActorAnimationOperations()).sampled_value(actor,path,time,value);
    }
    public Variant copy_value(Variant value)
    {
        if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource){if(ScriptIs(resource,"res://scripts/actors/physics/destruction/physics_bake_cache.gd"))return resource;if(ScriptIs(resource,"res://scripts/actors/core/actor_object_reference.gd"))return copy_reference(resource);if(ScriptIs(resource,"res://scripts/actors/core/actor_object_data.gd"))return copy_object(resource);return resource.Duplicate(true);}if(value.VariantType==Variant.Type.Dictionary){var result=new Settings();foreach(var entry in value.AsGodotDictionary())result[entry.Key]=copy_value(entry.Value);return result;}if(value.VariantType==Variant.Type.Array){var result=value.AsGodotArray().Duplicate();for(int i=0;i<result.Count;i++)result[i]=copy_value(result[i]);return result;}return value;
    }
    public Resource copy_object(Resource resource){var result=New("actor_object_data");result.Set("type_id",resource.Get("type_id"));result.Set("schema_version",resource.Get("schema_version"));result.Set("values",copy_value(resource.Get("values")));return result;}
    public Resource copy_actor(Resource actor){var result=New("actor_data");result.Set("id",new_id());foreach(string key in new[]{"type_id","display_name","parent_id","section_id","show_timeline_children","link_timeline_children","schema_version"})result.Set(key,actor.Get(key));result.Set("values",copy_value(actor.Get("values")));var tracks=result.Get("animation_tracks").AsGodotArray();foreach(var track in actor.Get("animation_tracks").AsGodotArray())tracks.Add(track.As<Resource>().Call("copy_track"));return result;}
    public Resource from_object(Resource resource){var reference=New("actor_object_reference");reference.Set("object_type",resource.Get("type_id"));reference.Set("embedded",resource);return reference;}
    public Resource from_asset(string id,StringName type){var reference=New("actor_object_reference");reference.Set("source",1);reference.Set("object_type",type);reference.Set("asset_id",id);return reference;}
    public Resource? resolve(Resource reference,Variant resolver)
    {
        var resource=reference.Get("embedded").As<Resource>();if(reference.Get("source").AsInt32()==1){if(reference.Get("asset_id").AsString().Length==0)return null;var resolved=reference.Call("_resolve_asset",resolver);resource=resolved.VariantType==Variant.Type.Object?resolved.AsGodotObject() as Resource:null;if(!ScriptIs(resource,"res://scripts/actors/core/actor_object_data.gd"))return null;}return resource!=null&&resource.Get("type_id").AsString()==reference.Get("object_type").AsString()?resource:null;
    }
    public Resource? make_unique(Resource reference,Variant resolver){var resource=resolve(reference,resolver);return resource!=null?from_object(copy_object(resource)):null;}
    public Resource copy_reference(Resource resource)
    {
        if(resource.Get("source").AsInt32()==1)return from_asset(resource.Get("asset_id").AsString(),resource.Get("object_type").AsStringName());var embedded=resource.Get("embedded").As<Resource>();if(embedded!=null)return from_object(copy_object(embedded));var result=New("actor_object_reference");result.Set("object_type",resource.Get("object_type"));return result;
    }
}
