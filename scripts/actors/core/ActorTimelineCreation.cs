using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorTimelineOperations
{
    public Resource? create_actor(RefCounted owner,Resource definition,double time,Settings initial)
    {
        var model=Get(initial,new StringName("mesh_path"),"");
        if(definition.Get("type_id").AsString()=="basic_mesh"&&(model.VariantType==Variant.Type.Object||model.VariantType==Variant.Type.String&&model.AsString().Length>0))
        {
            string path=model.VariantType==Variant.Type.Object?model.As<Resource>().ResourcePath:model.AsString();
            var document=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_import.gd").Call("load_document",model).As<Resource>();
            if(document.Get("components").AsGodotArray().Count>0&&document.Call("validate").AsStringArray().Length==0)return instantiate_model(owner,document,path,time);
        }
        var actor=_definitions.create_actor(definition,initial);actor.Set("section_id",owner.Get("selected_section_id"));validate_focus(owner);actor.Set("parent_id",owner.Get("focused_actor_id"));
        var clip=_runtime.create_clip(actor,Math.Max(time,0),5);string type=actor.Get("type_id").AsString();var values=actor.Get("values").AsGodotDictionary();
        if(type=="transform_image_2d"){var asset=GD.Load<CSharpScript>("res://scripts/actors/core/ActorTransformationStates.cs").Call("load_asset",actor).AsGodotDictionary();var document=Get(asset,"document",default);if(document.VariantType==Variant.Type.Object&&document.AsGodotObject()!=null)clip.Set("duration",Math.Max(.1,document.AsGodotObject().Get("duration").AsDouble()));}
        if(type is "video" or "video_2d"){var source=Video.Call("info",Get(values,new StringName("video"),"").AsString()).AsGodotDictionary();if(source.Count==0)return null;clip.Set("duration",source["duration"]);actor.Set("show_timeline_children",false);actor.Set("link_timeline_children",true);}
        if(type=="audio"){double speed=Math.Clamp(Get(values,new StringName("speed"),1.0).AsDouble(),.25,4);clip.Set("playback_speed",speed);clip.Set("duration",GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("length",actor).AsDouble()/speed);if(clip.Get("duration").AsDouble()<=0)return null;}
        clip.Set("layer",owner.Get("selected_layer"));var neighbors=new List<Resource>();foreach(var value in section_clips(owner)){var other=value.As<Resource>();if(other.Get("layer").AsInt32()==clip.Get("layer").AsInt32()&&actors_obstruct(owner,actor,actor_for_id(owner,other.Get("actor_id").AsString())))neighbors.Add(other);}neighbors.Sort((a,b)=>a.Get("start_time").AsDouble().CompareTo(b.Get("start_time").AsDouble()));
        foreach(var other in neighbors)if(clip.Get("start_time").AsDouble()<other.Get("start_time").AsDouble()+other.Get("duration").AsDouble()&&clip.Get("start_time").AsDouble()+clip.Get("duration").AsDouble()>other.Get("start_time").AsDouble())clip.Set("start_time",other.Get("start_time").AsDouble()+other.Get("duration").AsDouble());
        if(type is "video" or "video_2d"){var before=media_snapshot(owner);Actors(owner).Add(actor);Clips(owner).Add(clip);configure_video_audio(owner,actor);select(owner,clip.Get("id").AsString(),false);commit_media(owner,before,"Create Video");return clip;}
        History(owner,"Create "+definition.Get("display_name").AsString(),"_insert",new GArray{actor,clip,Clips(owner).Count,clip.Get("id")},"_remove",new GArray{clip.Get("id"),owner.Get("selected_id")});Changed(owner);return clip;
    }
    public Resource? instantiate_model(RefCounted owner,Resource document,string path,double start)
    {
        var registry=new ActorRegistry();GD.Load<GDScript>("res://scripts/actors/examples/basic_actors.gd").Call("register_all",registry);var scene=document.Call("actor_scene",registry,path).As<Resource>();if(scene.Get("actors").AsGodotArray().Count==0)return null;validate_focus(owner);return instantiate_scene(owner,scene,registry.Call("get_definition",new StringName("point_3d")).As<Resource>(),start,owner.Get("selected_layer").AsInt32(),path.Length>0?path.GetFile().GetBaseName():"Model","Instantiate Model");
    }
    private static void RemapActorLinks(Resource actor,Settings ids,bool clearExternal)
    {
        var values=actor.Get("values").AsGodotDictionary();if(Get(values,new StringName("physics"),default).VariantType==Variant.Type.Dictionary)values[new StringName("physics")]=GD.Load<GDScript>("res://scripts/actors/physics/physics_settings.gd").Call("remap",values[new StringName("physics")],ids);
        if(values.ContainsKey(new StringName("structure_connections")))GD.Load<GDScript>("res://scripts/actors/physics/structure/structure_definition.gd").Call("remap_actor",actor,ids);
        GD.Load<GDScript>("res://scripts/actors/fog/fog_motion_definition.gd").Call("remap_actor",actor,ids,clearExternal);
        foreach(string key in new[]{"fluid_mesh_actor","powder_mesh_actor"})if(values.ContainsKey(new StringName(key)))values[new StringName(key)]=Get(ids,values[new StringName(key)].AsString(),values[new StringName(key)]);
    }
    public Resource? instantiate_scene(RefCounted owner,Resource? scene,Resource? definition,double start,int layer,string name,string label)
    {
        if(scene==null||definition==null||definition.Get("type_id").AsString()!="point_3d")return null;var sourceClips=scene.Get("clips").AsGodotArray();var sourceActors=scene.Get("actors").AsGodotArray();var sections=scene.Get("sections").AsGodotArray();double first=double.PositiveInfinity,last=double.NegativeInfinity;int lowest=int.MaxValue;
        foreach(var value in sourceClips){var clip=value.As<Resource>();double time=clip.Get("start_time").AsDouble();first=Math.Min(first,time);last=Math.Max(last,time+clip.Get("duration").AsDouble());lowest=Math.Min(lowest,clip.Get("layer").AsInt32());}if(!double.IsFinite(first))first=0;double length=double.IsFinite(last)?Math.Max(last-first,.1):5;
        var root=_definitions.create_actor(definition,new Settings());root.Set("display_name",name.Length>0?name:"Scene");root.Set("section_id",owner.Get("selected_section_id"));root.Set("parent_id",owner.Get("focused_actor_id"));root.Set("show_timeline_children",false);root.Set("link_timeline_children",true);var rootClip=_runtime.create_clip(root,Math.Max(start,0),length);rootClip.Set("layer",Math.Max(0,layer));
        while(!can_place(owner,"",rootClip.Get("start_time").AsDouble(),length,rootClip.Get("layer").AsInt32())){double next=rootClip.Get("start_time").AsDouble()+.1;foreach(var value in section_clips(owner)){var other=value.As<Resource>();double time=other.Get("start_time").AsDouble();if(other.Get("layer").AsInt32()==rootClip.Get("layer").AsInt32()&&time<rootClip.Get("start_time").AsDouble()+length&&time+other.Get("duration").AsDouble()>rootClip.Get("start_time").AsDouble())next=Math.Max(next,time+other.Get("duration").AsDouble());}rootClip.Set("start_time",next);}
        var entries=new Godot.Collections.Array<Settings>{new Settings{["actor"]=root,["clip"]=rootClip}};var ids=new Settings();foreach(var value in sourceActors)ids[value.As<Resource>().Get("id")]=_data.new_id();var sectionParents=new Settings();
        if(sections.Count>1)foreach(var value in sections){var section=value.As<Resource>();var actor=_definitions.create_actor(definition,new Settings());actor.Set("display_name",section.Get("display_name"));actor.Set("section_id",owner.Get("selected_section_id"));actor.Set("parent_id",root.Get("id"));actor.Set("show_timeline_children",true);actor.Set("link_timeline_children",true);var clip=_runtime.create_clip(actor,rootClip.Get("start_time").AsDouble(),length);clip.Set("layer",rootClip.Get("layer").AsInt32()+1+sectionParents.Count);sectionParents[section.Get("id")]=actor.Get("id");entries.Add(new Settings{["actor"]=actor,["clip"]=clip});}
        for(int index=0;index<Math.Min(sourceActors.Count,sourceClips.Count);index++)
        {
            var source=sourceActors[index].As<Resource>();var sourceClip=sourceClips[index].As<Resource>();var actor=_data.copy_actor(source);actor.Set("id",ids[source.Get("id")]);foreach(var track in actor.Get("animation_tracks").AsGodotArray())foreach(var key in track.As<Resource>().Get("keys").AsGodotArray())key.As<Resource>().Set("id",_data.new_id());actor.Set("section_id",owner.Get("selected_section_id"));actor.Set("parent_id",Get(ids,source.Get("parent_id").AsString(),Get(sectionParents,source.Get("section_id").AsString(),root.Get("id"))));var values=actor.Get("values").AsGodotDictionary();
            foreach(string key in new[]{"linked_audio_actor","remote_actor","model_skeleton_actor","model_component_instance_id"})if(values.ContainsKey(new StringName(key)))values[new StringName(key)]=Get(ids,values[new StringName(key)].AsString(),"");if(values.ContainsKey(new StringName("model_component_bind_transform"))&&Get(values,new StringName("model_component_instance_id"),"").AsString().Length==0)values[new StringName("model_component_instance_id")]=root.Get("id");RemapActorLinks(actor,ids,true);
            var clip=sourceClip.Duplicate(true);clip.Set("id",_data.new_id());clip.Set("actor_id",actor.Get("id"));clip.Set("start_time",rootClip.Get("start_time").AsDouble()+sourceClip.Get("start_time").AsDouble()-first);clip.Set("layer",rootClip.Get("layer").AsInt32()+sections.Count+1+sourceClip.Get("layer").AsInt32()-lowest);
            var physics=Get(values,new StringName("physics"),new Settings()).AsGodotDictionary();var bake=Get(physics,"bake",new Settings()).AsGodotDictionary();if(Get(bake,"portable",false).AsBool()){bake["portable_root"]=root.Get("id");bake["owner"]=actor.Get("id");bake["portable_authored"]=GD.Load<GDScript>("res://scripts/actors/physics/destruction/bake_editing.gd").Call("portable_signature",actor);}entries.Add(new Settings{["actor"]=actor,["clip"]=clip});
        }
        var clipIds=new Godot.Collections.Array<string>();foreach(var entry in entries)clipIds.Add(entry["clip"].As<Resource>().Get("id").AsString());var selection=new Godot.Collections.Array<string>{rootClip.Get("id").AsString()};History(owner,label,"_insert_copies",new GArray{entries,selection},"_remove_copies",new GArray{clipIds,Selected(owner).Duplicate()});return rootClip;
    }
}

