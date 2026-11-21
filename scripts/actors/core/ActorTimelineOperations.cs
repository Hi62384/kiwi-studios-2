using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorTimelineOperations:RefCounted
{
    private static GArray Actors(RefCounted owner)=>owner.Get("actors").AsGodotArray();private static GArray Clips(RefCounted owner)=>owner.Get("clips").AsGodotArray();private static GArray Selected(RefCounted owner)=>owner.Get("selected_ids").AsGodotArray();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static void Changed(RefCounted owner)=>owner.EmitSignal("changed");
    public int index_of(RefCounted owner,string id){var clips=Clips(owner);for(int i=0;i<clips.Count;i++)if(clips[i].As<Resource>().Get("id").AsString()==id)return i;return -1;}
    public Resource? actor_for_id(RefCounted owner,string id){foreach(var value in Actors(owner)){var actor=value.As<Resource>();if(actor.Get("id").AsString()==id)return actor;}return null;}
    public Resource? clip_for_actor_id(RefCounted owner,string id){var actors=Actors(owner);for(int i=0;i<actors.Count;i++)if(actors[i].As<Resource>().Get("id").AsString()==id)return Clips(owner)[i].As<Resource>();return null;}
    public Resource? selected_actor(RefCounted owner){int index=index_of(owner,owner.Get("selected_id").AsString());return index>=0?Actors(owner)[index].As<Resource>():null;}
    public Resource? selected_clip(RefCounted owner){int index=index_of(owner,owner.Get("selected_id").AsString());return index>=0?Clips(owner)[index].As<Resource>():null;}
    public GArray selected_actors(RefCounted owner){var result=new GArray();foreach(var id in Selected(owner)){int index=index_of(owner,id.AsString());if(index>=0)result.Add(Actors(owner)[index]);}return result;}
    public Resource? section_for_id(RefCounted owner,string id){foreach(var value in owner.Get("sections").AsGodotArray()){var section=value.As<Resource>();if(section.Get("id").AsString()==id)return section;}return null;}
    private IEnumerable<Resource> Ancestors(RefCounted owner,Resource actor)
    {
        var current=actor_for_id(owner,actor.Get("parent_id").AsString());var visited=new HashSet<string>();while(current!=null&&visited.Add(current.Get("id").AsString())){yield return current;current=actor_for_id(owner,current.Get("parent_id").AsString());}
    }
    public string actor_path(RefCounted owner,string id){var names=new List<string>();var current=actor_for_id(owner,id);var visited=new HashSet<string>();while(current!=null&&visited.Add(current.Get("id").AsString())){names.Insert(0,current.Get("display_name").AsString());current=actor_for_id(owner,current.Get("parent_id").AsString());}return string.Join(" / ",names);}
    public Settings navigation_state(RefCounted owner)=>owner.Get("_section_navigation").AsGodotDictionary().Duplicate(true);
    public void restore_navigation_state(RefCounted owner,Settings state)=>owner.Set("_section_navigation",state.Duplicate(true));
    public void validate_focus(RefCounted owner){var actor=actor_for_id(owner,owner.Get("focused_actor_id").AsString());if(actor==null||actor.Get("section_id").AsString()!=owner.Get("selected_section_id").AsString())owner.Set("focused_actor_id","");}
    public void focus_actor(RefCounted owner,string id){var actor=actor_for_id(owner,id);if(actor==null||actor.Get("section_id").AsString()!=owner.Get("selected_section_id").AsString())return;if(owner.Get("focused_actor_id").AsString()==id){focus_parent(owner);return;}owner.Set("focused_actor_id",actor.Get("id"));set_single_selection(owner,clip_for_actor_id(owner,actor.Get("id").AsString())!.Get("id").AsString());owner.Set("selected_layer",selected_clip(owner)!.Get("layer"));Changed(owner);}
    public void leave_actor_focus(RefCounted owner){owner.Set("focused_actor_id","");Selected(owner).Clear();owner.Set("selected_id","");Changed(owner);}
    public void focus_parent(RefCounted owner){validate_focus(owner);var actor=actor_for_id(owner,owner.Get("focused_actor_id").AsString());if(actor==null)return;string parent=actor.Get("parent_id").AsString();if(parent.Length==0)leave_actor_focus(owner);else focus_actor(owner,parent);}
    public GArray focus_path(RefCounted owner){validate_focus(owner);var result=new GArray();var actor=actor_for_id(owner,owner.Get("focused_actor_id").AsString());var visited=new HashSet<string>();while(actor!=null&&visited.Add(actor.Get("id").AsString())){result.Insert(0,actor);actor=actor_for_id(owner,actor.Get("parent_id").AsString());}return result;}
    public void select_section(RefCounted owner,string id)
    {
        if(section_for_id(owner,id)==null)return;string previous=owner.Get("selected_section_id").AsString();if(id==previous){Changed(owner);return;}var navigation=owner.Get("_section_navigation").AsGodotDictionary();navigation[previous]=new Settings{["focus"]=owner.Get("focused_actor_id"),["selection"]=Selected(owner).Duplicate(),["layer"]=owner.Get("selected_layer")};owner.Set("selected_section_id",id);var state=Get(navigation,id,new Settings()).AsGodotDictionary();owner.Set("focused_actor_id",Get(state,"focus",""));validate_focus(owner);var selected=Selected(owner);selected.Clear();foreach(var clipId in Get(state,"selection",new GArray()).AsGodotArray()){int index=index_of(owner,clipId.AsString());if(index>=0&&Actors(owner)[index].As<Resource>().Get("section_id").AsString()==id)selected.Add(clipId);}owner.Set("selected_id",selected.Count>0?selected[selected.Count-1]:Variant.From(""));owner.Set("selected_layer",Get(state,"layer",0));Changed(owner);
    }
    public bool clip_is_visible(RefCounted owner,int index)
    {
        var actors=Actors(owner);if(index<0||index>=actors.Count)return false;var actor=actors[index].As<Resource>();if(actor.Get("section_id").AsString()!=owner.Get("selected_section_id").AsString())return false;validate_focus(owner);string focused=owner.Get("focused_actor_id").AsString();if(actor.Get("id").AsString()==focused)return true;foreach(var ancestor in Ancestors(owner,actor)){if(ancestor.Get("id").AsString()==focused)return true;if(!ancestor.Get("show_timeline_children").AsBool())return false;}return focused.Length==0;
    }
    public GArray section_clips(RefCounted owner){var result=new GArray();var actors=Actors(owner);var clips=Clips(owner);string section=owner.Get("selected_section_id").AsString();for(int i=0;i<clips.Count;i++)if(actors[i].As<Resource>().Get("section_id").AsString()==section)result.Add(clips[i]);return result;}
    public string visibility_domain(RefCounted owner,Resource actor){foreach(var ancestor in Ancestors(owner,actor))if(!ancestor.Get("show_timeline_children").AsBool())return ancestor.Get("id").AsString();return "section:"+actor.Get("section_id").AsString();}
    public bool actor_in_focus(RefCounted owner,Resource? actor){string focus=owner.Get("focused_actor_id").AsString();if(focus.Length==0||actor==null)return false;if(actor.Get("id").AsString()==focus)return true;foreach(var ancestor in Ancestors(owner,actor))if(ancestor.Get("id").AsString()==focus)return true;return false;}
    public bool visible_in_focused_branch(RefCounted owner,Resource actor){string focus=owner.Get("focused_actor_id").AsString();if(focus.Length==0)return false;if(actor.Get("id").AsString()==focus)return true;foreach(var ancestor in Ancestors(owner,actor)){if(ancestor.Get("id").AsString()==focus)return true;if(!ancestor.Get("show_timeline_children").AsBool())return false;}return false;}
    public bool is_focus_ancestor(RefCounted owner,Resource actor){var focus=actor_for_id(owner,owner.Get("focused_actor_id").AsString());return focus!=null&&is_actor_ancestor(owner,actor.Get("id").AsString(),focus);}
    public bool is_actor_ancestor(RefCounted owner,string id,Resource actor){foreach(var parent in Ancestors(owner,actor))if(parent.Get("id").AsString()==id)return true;return false;}
    public bool unbroken_relative_path(RefCounted owner,string id,Resource actor){foreach(var parent in Ancestors(owner,actor)){if(parent.Get("id").AsString()==id)return true;if(!parent.Get("show_timeline_children").AsBool())return false;}return false;}
    public bool actors_obstruct(RefCounted owner,Resource? a,Resource? b)
    {
        if(a==null||b==null||a.Get("section_id").AsString()!=b.Get("section_id").AsString())return false;if(is_actor_ancestor(owner,a.Get("id").AsString(),b))return unbroken_relative_path(owner,a.Get("id").AsString(),b);if(is_actor_ancestor(owner,b.Get("id").AsString(),a))return unbroken_relative_path(owner,b.Get("id").AsString(),a);if(a.Get("section_id").AsString()==owner.Get("selected_section_id").AsString()&&visible_in_focused_branch(owner,a)&&visible_in_focused_branch(owner,b))return true;return visibility_domain(owner,a)==visibility_domain(owner,b);
    }
    public bool hidden_clip_obstructs_view(RefCounted owner,int index)
    {
        var clips=Clips(owner);if(index<0||index>=clips.Count||clip_is_visible(owner,index))return false;int displayed=0;bool blocksAll=true;for(int other=0;other<clips.Count;other++){if(!clip_is_visible(owner,other))continue;displayed++;bool blocks=actors_obstruct(owner,Actors(owner)[index].As<Resource>(),Actors(owner)[other].As<Resource>());if(blocks&&is_selected(owner,clips[other].As<Resource>().Get("id").AsString()))return true;blocksAll&=blocks;}return Selected(owner).Count==0&&displayed>0&&blocksAll;
    }
    public GArray visible_clips(RefCounted owner){var result=new GArray();var clips=Clips(owner);for(int i=0;i<clips.Count;i++)if(clip_is_visible(owner,i))result.Add(clips[i]);return result;}
    public int layer_count(RefCounted owner){int count=Math.Max(3,owner.Get("selected_layer").AsInt32()+2);foreach(var value in visible_clips(owner))count=Math.Max(count,value.As<Resource>().Get("layer").AsInt32()+2);var clips=Clips(owner);for(int i=0;i<clips.Count;i++)if(hidden_clip_obstructs_view(owner,i))count=Math.Max(count,clips[i].As<Resource>().Get("layer").AsInt32()+2);return count;}
    public bool is_selected(RefCounted owner,string id)=>Selected(owner).Contains(id);
    public void set_single_selection(RefCounted owner,string id){var selected=Selected(owner);selected.Clear();if(index_of(owner,id)>=0){selected.Add(id);owner.Set("selected_id",id);}else owner.Set("selected_id","");}
    public void make_primary(RefCounted owner,string id){if(index_of(owner,id)<0)return;var selected=Selected(owner);selected.Remove(id);selected.Add(id);owner.Set("selected_id",id);}
    public void select(RefCounted owner,string id,bool additive)
    {
        owner.EmitSignal("selection_requested");int index=index_of(owner,id);if(index>=0){string section=Actors(owner)[index].As<Resource>().Get("section_id").AsString();if(section!=owner.Get("selected_section_id").AsString())select_section(owner,section);}var selected=Selected(owner);index=index_of(owner,id);if(index<0){selected.Clear();owner.Set("selected_id","");}else{if(!additive)selected.Clear();else selected.Remove(id);selected.Add(id);owner.Set("selected_id",id);owner.Set("selected_layer",Clips(owner)[index].As<Resource>().Get("layer"));}Changed(owner);
    }
    public void select_all(RefCounted owner)
    {
        owner.EmitSignal("selection_requested");string previous=owner.Get("selected_id").AsString();var selected=Selected(owner);selected.Clear();foreach(var value in visible_clips(owner)){var clip=value.As<Resource>();if(clip.Get("id").AsString()!=previous)selected.Add(clip.Get("id"));}if(clip_is_visible(owner,index_of(owner,previous))){selected.Add(previous);owner.Set("selected_id",previous);}else if(selected.Count>0){owner.Set("selected_id",selected[selected.Count-1]);owner.Set("selected_layer",selected_clip(owner)!.Get("layer"));}else owner.Set("selected_id","");Changed(owner);
    }
    public void set_selection(RefCounted owner,GArray ids,string primary)
    {
        owner.EmitSignal("selection_requested");var incoming=ids.Duplicate();var selected=Selected(owner);selected.Clear();foreach(var value in incoming){string id=value.AsString();int index=index_of(owner,id);if(index>=0&&Actors(owner)[index].As<Resource>().Get("section_id").AsString()==owner.Get("selected_section_id").AsString()&&!selected.Contains(id))selected.Add(id);}if(selected.Contains(primary)){selected.Remove(primary);selected.Add(primary);}owner.Set("selected_id",selected.Count>0?selected[selected.Count-1]:Variant.From(""));var clip=selected_clip(owner);if(clip!=null)owner.Set("selected_layer",clip.Get("layer"));Changed(owner);
    }
    public void toggle_selection(RefCounted owner,string id){if(index_of(owner,id)<0)return;var next=Selected(owner).Duplicate();if(next.Contains(id)){next.Remove(id);set_selection(owner,next,next.Count>0?next[next.Count-1].AsString():"");}else{next.Add(id);set_selection(owner,next,id);}}
    public void undo(RefCounted owner){var history=owner.Get("history").As<UndoRedo>();if(history.HasUndo())history.Undo();Changed(owner);}
    public void redo(RefCounted owner){var history=owner.Get("history").As<UndoRedo>();if(history.HasRedo())history.Redo();Changed(owner);}
}
