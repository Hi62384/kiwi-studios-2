using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorTimelineOperations
{
    private readonly ActorPropertyOperations _properties=new();
    public bool values_equal(Variant left,Variant right)=>left.VariantType==right.VariantType&&Equal(left,right);
    public void edit_property(RefCounted owner,Resource actor,Resource definition,StringName key,Variant value)
    {
        var property=_definitions.find_property(definition,key);if(!Actors(owner).Contains(actor)||property==null||!_properties.accepts(property,value)||actor.Get("type_id").AsString()!=definition.Get("type_id").AsString())return;string[] path={key.ToString()};if(_data.animation_track(actor,path)!=null){commit_animation_value(owner,actor,path,value);return;}if(values_equal(_data.get_value(actor,key,default),value))return;string type=actor.Get("type_id").AsString(),name=key.ToString();if((type is "video" or "video_2d")&&(name is "video" or "linked_audio_actor")){edit_video_property(owner,actor,key,value);return;}bool batch=owner.Get("property_batch_active").AsBool();if(type=="audio"&&(name is "speed" or "audio")&&!batch){var before=audio_snapshot(owner,actor);set_property(owner,actor,key,value);History(owner,"Change "+property.Get("label").AsString(),"restore_audio",new GArray{audio_snapshot(owner,actor)},"restore_audio",new GArray{before});return;}if(batch){set_property(owner,actor,key,value);return;}History(owner,"Change "+property.Get("label").AsString(),"_set_property",new GArray{actor,key,_data.copy_value(value)},"_set_property",new GArray{actor,key,_data.copy_value(_data.get_value(actor,key,default))});Changed(owner);
    }
    public void preview_property(RefCounted owner,Resource actor,Resource definition,StringName key,Variant value)
    {
        var property=_definitions.find_property(definition,key);if(!Actors(owner).Contains(actor)||property==null||!_properties.accepts(property,value)||actor.Get("type_id").AsString()!=definition.Get("type_id").AsString())return;var previews=owner.Get("_audio_preview_before").AsGodotDictionary();if(actor.Get("type_id").AsString()=="audio"&&(key.ToString() is "speed" or "audio")&&!previews.ContainsKey(actor.Get("id")))previews[actor.Get("id")]=audio_snapshot(owner,actor);string[] path={key.ToString()};if(_data.animation_track(actor,path)!=null){preview_animation_value(owner,actor,path,value);return;}set_property(owner,actor,key,value);
    }
    public void commit_property_preview(RefCounted owner,Resource actor,Resource definition,StringName key,Variant original,Variant final)
    {
        var property=_definitions.find_property(definition,key);string[] path={key.ToString()};bool present=Actors(owner).Contains(actor),accepted=property!=null&&_properties.accepts(property,final);if(present&&accepted&&_data.animation_track(actor,path)!=null){commit_animation_value(owner,actor,path,final);return;}if(!present||!accepted||values_equal(original,final))return;var previews=owner.Get("_audio_preview_before").AsGodotDictionary();if(owner.Get("property_batch_active").AsBool()){set_property(owner,actor,key,final);previews.Remove(actor.Get("id"));return;}if(actor.Get("type_id").AsString()=="audio"&&previews.TryGetValue(actor.Get("id"),out var captured)){previews.Remove(actor.Get("id"));set_property(owner,actor,key,final);History(owner,"Change "+property!.Get("label").AsString(),"restore_audio",new GArray{audio_snapshot(owner,actor)},"restore_audio",new GArray{captured});return;}History(owner,"Change "+property!.Get("label").AsString(),"_set_property",new GArray{actor,key,_data.copy_value(final)},"_set_property",new GArray{actor,key,_data.copy_value(original)});Changed(owner);
    }
    public void set_property(RefCounted owner,Resource actor,StringName key,Variant value)
    {
        if(actor.Get("type_id").AsString()=="audio"&&(key.ToString() is "speed" or "audio")){var clip=clip_for_actor_id(owner,actor.Get("id").AsString());if(clip!=null){if(key.ToString()=="speed"){double speed=value.AsDouble();if(!double.IsFinite(speed))return;speed=Math.Clamp(speed,.25,4);value=speed;clip.Set("duration",clip.Get("duration").AsDouble()*clip.Get("playback_speed").AsDouble()/speed);clip.Set("playback_speed",speed);}else{var stream=GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("source",value).As<AudioStream>();if(stream==null&&value.VariantType!=Variant.Type.Nil&&value.ToString().Length>0)return;clip.Set("source_offset",0.0);clip.Set("duration",stream!=null?stream.GetLength()/clip.Get("playback_speed").AsDouble():.1);}while(!can_place(owner,clip.Get("id").AsString(),clip.Get("start_time").AsDouble(),clip.Get("duration").AsDouble(),clip.Get("layer").AsInt32()))clip.Set("layer",clip.Get("layer").AsInt32()+1);}}_data.set_value(actor,key,_data.copy_value(value));Changed(owner);
    }
    public void edit_object_property(RefCounted owner,Resource actor,Resource? resource,Resource? definition,StringName key,Variant value)
    {
        if(!Actors(owner).Contains(actor)||resource==null||definition==null)return;var property=_definitions.find_property(definition,key);if(property!=null&&_properties.accepts(property,value)&&animated_object_edit(owner,actor,resource,key,value,false))return;if(property==null||!_properties.accepts(property,value)||values_equal(_definitions.value_for(resource,property),value))return;var original=_data.copy_value(_definitions.value_for(resource,property));History(owner,"Change "+property.Get("label").AsString(),"_set_object_property",new GArray{resource,key,_data.copy_value(value)},"_set_object_property",new GArray{resource,key,original});Changed(owner);
    }
    public void preview_object_property(RefCounted owner,Resource actor,Resource? resource,Resource? definition,StringName key,Variant value)
    {
        var property=definition!=null?_definitions.find_property(definition,key):null;if(!Actors(owner).Contains(actor)||resource==null||property==null||!_properties.accepts(property,value))return;if(animated_object_edit(owner,actor,resource,key,value,true))return;set_object_property(owner,resource,key,value);
    }
    public void commit_object_property_preview(RefCounted owner,Resource actor,Resource? resource,Resource? definition,StringName key,Variant original,Variant final)
    {
        var property=definition!=null?_definitions.find_property(definition,key):null;bool valid=Actors(owner).Contains(actor)&&resource!=null&&property!=null&&_properties.accepts(property,final);if(valid&&animated_object_edit(owner,actor,resource!,key,final,false))return;if(!valid||Equal(original,final))return;History(owner,"Change "+property!.Get("label").AsString(),"_set_object_property",new GArray{resource!,key,_data.copy_value(final)},"_set_object_property",new GArray{resource!,key,_data.copy_value(original)});Changed(owner);
    }
    public void set_object_property(RefCounted owner,Resource resource,StringName key,Variant value)
    {
        _data.set_value(resource,key,_data.copy_value(value));string path=resource.ResourcePath;if(path.Length>0){int marker=path.IndexOf("::",StringComparison.Ordinal);string rootPath=marker>=0?path.Substring(0,marker):path;var root=marker>=0?ResourceLoader.Load(rootPath):resource;if(root!=null&&ActorDataOperations.ScriptIs(root,"res://scripts/actors/core/actor_object_data.gd")){root.EmitChanged();ResourceSaver.Save(root,rootPath);}}Changed(owner);
    }
}
