using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorTimelineOperations
{
    private static Variant Optional(GodotObject? value)=>value!=null?Variant.From(value):default;
    public void delete_section(RefCounted owner,string id)
    {
        var section=section_for_id(owner,id);if(section==null)return;var entries=new Godot.Collections.Array<Settings>();var actors=Actors(owner);var clips=Clips(owner);for(int i=0;i<actors.Count;i++)if(actors[i].As<Resource>().Get("section_id").AsString()==id)entries.Add(new Settings{["actor"]=actors[i],["clip"]=clips[i],["index"]=i});Resource? replacement=null;var sections=owner.Get("sections").AsGodotArray();if(sections.Count==1){replacement=new ActorSection();replacement.Set("id",_data.new_id());}History(owner,"Delete Section","_delete_section_state",new GArray{section,entries,Optional(replacement)},"_restore_section_state",new GArray{section,sections.IndexOf(section),entries,Optional(replacement),owner.Get("selected_section_id"),Selected(owner).Duplicate()});
    }
    public void delete_section_state(RefCounted owner,Resource section,GArray entries,Resource? replacement)
    {
        foreach(var value in entries){int index=index_of(owner,value.AsGodotDictionary()["clip"].As<Resource>().Get("id").AsString());if(index>=0){Actors(owner).RemoveAt(index);Clips(owner).RemoveAt(index);}}var sections=owner.Get("sections").AsGodotArray();sections.Remove(section);if(replacement!=null)sections.Add(replacement);if(owner.Get("selected_section_id").AsString()==section.Get("id").AsString())select_section(owner,sections[0].As<Resource>().Get("id").AsString());else Changed(owner);
    }
    public void restore_section_state(RefCounted owner,Resource section,int index,GArray entries,Resource? replacement,string previous,GArray selection)
    {
        var sections=owner.Get("sections").AsGodotArray();if(replacement!=null)sections.Remove(replacement);sections.Insert(index,section);foreach(var value in entries){var entry=value.AsGodotDictionary();Actors(owner).Insert(entry["index"].AsInt32(),entry["actor"]);Clips(owner).Insert(entry["index"].AsInt32(),entry["clip"]);}owner.Set("selected_section_id",previous);Assign(Selected(owner),selection);owner.Set("selected_id",Selected(owner).Count>0?Selected(owner)[Selected(owner).Count-1]:Variant.From(""));var clip=selected_clip(owner);if(clip!=null)owner.Set("selected_layer",clip.Get("layer"));Changed(owner);
    }
    public void move_to_section(RefCounted owner,GArray ids,string sectionId)
    {
        if(section_for_id(owner,sectionId)==null)return;var states=new Settings();var roots=ids.Duplicate();foreach(var value in ids){string id=value.AsString();var actor=actor_for_id(owner,id);if(actor==null)continue;foreach(var ancestor in Ancestors(owner,actor))if(ids.Contains(ancestor.Get("id"))){roots.Remove(id);break;}}foreach(var value in Actors(owner)){var actor=value.As<Resource>();var current=actor;var visited=new HashSet<string>();while(current!=null&&visited.Add(current.Get("id").AsString())){if(ids.Contains(current.Get("id"))){states[actor.Get("id")]=new Settings{["old_section"]=actor.Get("section_id"),["old_parent"]=actor.Get("parent_id"),["old_layer"]=clip_for_actor_id(owner,actor.Get("id").AsString())!.Get("layer"),["old_values"]=transform_values(actor),["new_parent"]=roots.Contains(actor.Get("id"))?Variant.From(""):actor.Get("parent_id"),["new_values"]=roots.Contains(actor.Get("id"))?values_for_preserved_world(owner,actor,""):transform_values(actor)};break;}current=actor_for_id(owner,current.Get("parent_id").AsString());}}if(states.Count==0)return;History(owner,"Move Actors to Section","_apply_section_move",new GArray{states,sectionId,true},"_apply_section_move",new GArray{states,owner.Get("selected_section_id"),false});
    }
    public void apply_section_move(RefCounted owner,Settings states,string sectionId,bool forward)
    {
        foreach(var entry in states){string id=entry.Key.AsString();var actor=actor_for_id(owner,id);if(actor==null)continue;var state=entry.Value.AsGodotDictionary();actor.Set("section_id",forward?Variant.From(sectionId):state["old_section"]);var clip=clip_for_actor_id(owner,id)!;clip.Set("layer",state["old_layer"]);if(forward)while(!can_place(owner,clip.Get("id").AsString(),clip.Get("start_time").AsDouble(),clip.Get("duration").AsDouble(),clip.Get("layer").AsInt32()))clip.Set("layer",clip.Get("layer").AsInt32()+1);apply_parent_state_silent(actor,state[forward?"new_parent":"old_parent"].AsString(),state[forward?"new_values":"old_values"].AsGodotDictionary());}select_section(owner,sectionId);
    }
}
