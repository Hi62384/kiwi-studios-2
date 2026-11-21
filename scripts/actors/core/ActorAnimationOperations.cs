using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ActorAnimationOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorAnimationTrackOperations _tracks=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(new StringName(key),out var value)||values.TryGetValue(key,out value)?value:fallback;
    public Resource? resolve_reference(Resource reference)
    {
        var resource=reference.Get("embedded").As<Resource>();if(reference.Get("source").AsInt32()==1){string path=reference.Get("asset_id").AsString();if(path.Length==0||!ResourceLoader.Exists(path))return null;resource=ResourceLoader.Load(path);if(!ActorDataOperations.ScriptIs(resource,"res://scripts/actors/core/actor_object_data.gd"))return null;}return resource!=null&&resource.Get("type_id").AsString()==reference.Get("object_type").AsString()?resource:null;
    }
    public Variant value_at_path(Resource actor,string[] path)
    {
        Variant value=actor.Get("values");foreach(string part in path){if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource){if(ActorDataOperations.ScriptIs(resource,"res://scripts/actors/core/actor_object_reference.gd")){var resolved=resolve_reference(resource);value=resolved!=null?Variant.From(resolved):default;}if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource data&&ActorDataOperations.ScriptIs(data,"res://scripts/actors/core/actor_object_data.gd"))value=data.Get("values");}if(value.VariantType!=Variant.Type.Dictionary)return default;value=Get(value.AsGodotDictionary(),part);}return value;
    }
    internal static Variant Component(Variant value,int index)=>value.VariantType switch{Variant.Type.Vector2=>Variant.From(value.AsVector2()[index]),Variant.Type.Vector3=>Variant.From(value.AsVector3()[index]),Variant.Type.Vector4=>Variant.From(value.AsVector4()[index]),Variant.Type.Vector2I=>Variant.From(value.AsVector2I()[index]),Variant.Type.Vector3I=>Variant.From(value.AsVector3I()[index]),Variant.Type.Vector4I=>Variant.From(value.AsVector4I()[index]),Variant.Type.Color=>Variant.From(value.AsColor()[index]),_=>throw new ArgumentException("Separated track base must have numeric components.")};
    internal static Variant WithComponent(Variant value,int index,Variant next)
    {
        switch(value.VariantType){case Variant.Type.Vector2:var v2=value.AsVector2();v2[index]=next.AsSingle();return v2;case Variant.Type.Vector3:var v3=value.AsVector3();v3[index]=next.AsSingle();return v3;case Variant.Type.Vector4:var v4=value.AsVector4();v4[index]=next.AsSingle();return v4;case Variant.Type.Vector2I:var i2=value.AsVector2I();i2[index]=next.AsInt32();return i2;case Variant.Type.Vector3I:var i3=value.AsVector3I();i3[index]=next.AsInt32();return i3;case Variant.Type.Vector4I:var i4=value.AsVector4I();i4[index]=next.AsInt32();return i4;case Variant.Type.Color:var color=value.AsColor();color[index]=next.AsSingle();return color;default:throw new ArgumentException("Separated track base must have numeric components.");}
    }
    public Variant sampled_value(Resource actor,string[] path,double time,Variant fallback)
    {
        var previews=actor.Get("animation_previews").AsGodotDictionary();if(previews.TryGetValue(string.Join(" / ",path),out var preview)&&preview.AsGodotDictionary().Count>0)return preview.AsGodotDictionary()["value"];var track=_data.animation_track(actor,path);if(track!=null&&track.Get("component").AsInt32()>=0){var combined=_data.copy_value(track.Get("component_base"));foreach(var value in actor.Get("animation_tracks").AsGodotArray()){var part=value.As<Resource>();int component=part.Get("component").AsInt32();if(component>=0&&part.Get("path").AsStringArray().SequenceEqual(path))combined=WithComponent(combined,component,_tracks.sample(part,time,Component(combined,component)));}return combined;}return track!=null?_tracks.sample(track,time,fallback):fallback;
    }
    public Settings sampled_values(Resource actor,double time)
    {
        var values=actor.Get("values").AsGodotDictionary().Duplicate();var sampled=new HashSet<string>();foreach(var value in actor.Get("animation_tracks").AsGodotArray()){var track=value.As<Resource>();if(track.Get("keys").AsGodotArray().Count==0)continue;var path=track.Get("path").AsStringArray();if(!sampled.Add(string.Join(" / ",path)))continue;set_path(values,path,sampled_value(actor,path,time,value_at_path(actor,path)),0);}foreach(var value in actor.Get("animation_previews").AsGodotDictionary().Values){var preview=value.AsGodotDictionary();set_path(values,preview["path"].AsStringArray(),preview["value"],0);}return values;
    }
    public void set_path(Settings container,string[] path,Variant value,int index)
    {
        if(index>=path.Length)return;StringName key=path[index];if(index==path.Length-1){container[key]=_data.copy_value(value);return;}var child=Get(container,path[index]);if(child.VariantType==Variant.Type.Nil&&path[index]=="physics")child=new Settings();if(child.VariantType==Variant.Type.Object&&child.AsGodotObject() is Resource reference&&ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd")){var resource=resolve_reference(reference);if(resource==null)return;var copy=new ActorObjectData();copy.Set("type_id",resource.Get("type_id"));var values=resource.Get("values").AsGodotDictionary().Duplicate();copy.Set("values",values);container[key]=_data.from_object(copy);set_path(values,path,value,index+1);}else if(child.VariantType==Variant.Type.Dictionary){var copy=child.AsGodotDictionary().Duplicate();container[key]=copy;set_path(copy,path,value,index+1);}
    }
    public string[] path_to_object(Resource actor,Resource target)=>find_object(actor.Get("values").AsGodotDictionary(),target,Array.Empty<string>(),new Settings());
    public string[] find_object(Settings values,Resource target,string[] prefix,Settings visited)
    {
        foreach(var entry in values){var next=new string[prefix.Length+1];Array.Copy(prefix,next,prefix.Length);next[^1]=entry.Key.ToString();if(entry.Value.VariantType==Variant.Type.Dictionary){var nested=find_object(entry.Value.AsGodotDictionary(),target,next,visited);if(nested.Length>0)return nested;}if(entry.Value.VariantType!=Variant.Type.Object||entry.Value.AsGodotObject() is not Resource reference||!ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd"))continue;var resource=resolve_reference(reference);if(resource==null)continue;if(resource==target||(target.ResourcePath.Length>0&&resource.ResourcePath==target.ResourcePath))return next;ulong id=resource.GetInstanceId();if(visited.ContainsKey(id))continue;var branch=visited.Duplicate();branch[id]=true;var found=find_object(resource.Get("values").AsGodotDictionary(),target,next,branch);if(found.Length>0)return found;}return Array.Empty<string>();
    }
}
