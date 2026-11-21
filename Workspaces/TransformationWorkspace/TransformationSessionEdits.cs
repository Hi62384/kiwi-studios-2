using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;

public partial class TransformationSessionOperations
{
    private static Resource MakeComponent(Vector2I size,string title)=>KiwiTransformationImage2D.make_component(size,title);
    public Resource add_component(RefCounted owner){var item=MakeComponent(Document(owner).Get("canvas_size").AsVector2I(),"Drawing "+(Components(owner).Count+1));begin(owner);Components(owner).Add(item);Assign(Array(owner,"selected"),new[]{item.Get("id")});commit(owner,"Add component");return item;}
    public void delete_components(RefCounted owner)
    {
        var selected=Array(owner,"selected");if(selected.Count==0)return;begin(owner);var components=Components(owner);for(int index=components.Count-1;index>=0;index--){var item=components[index].As<Resource>();if(Contains(selected,item.Get("id").AsString())&&!item.Get("locked").AsBool())components.RemoveAt(index);}var events=Document(owner).Get("component_events").AsGodotArray();for(int index=events.Count-1;index>=0;index--){var entry=events[index].AsGodotDictionary();bool valid=Component(owner,entry["target"].AsString())!=null;foreach(string id in entry["sources"].AsStringArray())valid&=Component(owner,id)!=null;if(!valid)events.RemoveAt(index);}selected.Clear();commit(owner,"Delete components");
    }
    public void copy_components(RefCounted owner){var clipboard=Array(owner,"clipboard");clipboard.Clear();foreach(var raw in Components(owner)){var item=raw.As<Resource>();if(Contains(Array(owner,"selected"),item.Get("id").AsString()))clipboard.Add(item.Call("copy_component",false));}}
    public void paste_components(RefCounted owner){var clipboard=Array(owner,"clipboard");if(clipboard.Count==0)return;begin(owner);var selected=Array(owner,"selected");selected.Clear();foreach(var raw in clipboard){var copy=raw.AsGodotObject().Call("copy_component",true).As<Resource>();copy.Set("title",copy.Get("title").AsString()+" copy");Components(owner).Add(copy);selected.Add(copy.Get("id"));}commit(owner,"Paste components");}
    public void duplicate_components(RefCounted owner){copy_components(owner);paste_components(owner);}
    public void reorder(RefCounted owner,string id,int target){var item=Component(owner,id);if(item==null||item.Get("locked").AsBool())return;var components=Components(owner);int old=components.IndexOf(item);target=Math.Clamp(target,0,components.Count-1);if(old==target)return;begin(owner);components.RemoveAt(old);components.Insert(target,item);commit(owner,"Reorder component");}
    public Resource? add_state(RefCounted owner,bool blank)
    {
        var item=primary(owner);var current=active_state(owner,item);if(item==null||current==null||item.Get("locked").AsBool())return null;var states=item.Get("states").AsGodotArray();var state=current.Call("copy_state",true).As<Resource>();state.Set("title","State "+(states.Count+1));if(blank){var art=KiwiImageLayer.create("basic",(Vector2I)item.Get("base_size").AsVector2());art.Set("id",item.Get("id"));art.Set("position",current.Get("artwork").AsGodotObject().Get("position"));art.Set("dimensions",current.Get("artwork").AsGodotObject().Get("dimensions"));state.Set("artwork",art);state.Set("title","Empty");}begin(owner);states.Add(state);Dict(owner,"edit_states")[item.Get("id")]=state.Get("id");commit(owner,"Create state");return state;
    }
    public void delete_state(RefCounted owner)
    {
        var item=primary(owner);var state=active_state(owner,item);if(item==null||state==null||item.Get("locked").AsBool()||item.Get("states").AsGodotArray().Count<2){owner.Set("message","Keep at least one state per component.");return;}begin(owner);var states=item.Get("states").AsGodotArray();states.Remove(state);var keys=item.Get("keys").AsGodotArray();string id=state.Get("id").AsString();for(int index=keys.Count-1;index>=0;index--)if(keys[index].AsGodotObject().Get("state_id").AsString()==id)keys.RemoveAt(index);var fallback=states[0].AsGodotObject().Get("id");Dict(owner,"edit_states")[item.Get("id")]=fallback;if(item.Get("default_state_id").AsString()==id)item.Set("default_state_id",fallback);commit(owner,"Delete state and its keys");
    }
    public void insert_key(RefCounted owner){var item=primary(owner);var state=active_state(owner,item);if(item==null||state==null||item.Get("locked").AsBool())return;begin(owner);double time=owner.Get("playhead").AsDouble();var key=key_at(item,time);if(key==null){key=new KiwiTransformationKey();key.Set("id",NewId());key.Set("time",time);item.Get("keys").AsGodotArray().Add(key);}key.Set("state_id",state.Get("id"));Assign(Array(owner,"selected_keys"),new[]{key.Get("id")});commit(owner,"Insert state key");}
    public void delete_keys(RefCounted owner){var selected=Array(owner,"selected_keys");if(selected.Count==0)return;begin(owner);foreach(var raw in Components(owner)){var item=raw.As<Resource>();if(item.Get("locked").AsBool())continue;var keys=item.Get("keys").AsGodotArray();for(int index=keys.Count-1;index>=0;index--)if(Contains(selected,keys[index].AsGodotObject().Get("id").AsString()))keys.RemoveAt(index);}selected.Clear();commit(owner,"Delete state keys");}
    public void duplicate_keys(RefCounted owner)
    {
        var selected=Array(owner,"selected_keys");if(selected.Count==0)return;begin(owner);var chosen=new List<Variant>();double duration=Document(owner).Get("duration").AsDouble();foreach(var raw in Components(owner)){var item=raw.As<Resource>();if(item.Get("locked").AsBool())continue;var keys=item.Get("keys").AsGodotArray();var snapshot=new List<Variant>(keys);foreach(var value in snapshot){var key=value.As<Resource>();if(!Contains(selected,key.Get("id").AsString()))continue;double time=Math.Min(duration,key.Get("time").AsDouble()+.1);while(key_at(item,time)!=null&&time<duration)time+=.001;if(time>duration||key_at(item,time)!=null)continue;var copy=key.Call("copy_key",true).As<Resource>();copy.Set("time",time);keys.Add(copy);chosen.Add(copy.Get("id"));}}Assign(selected,chosen);commit(owner,"Duplicate state keys");
    }
    public void set_duration(RefCounted owner,double value){double longest=0;foreach(var raw in Components(owner))foreach(var key in raw.AsGodotObject().Get("keys").AsGodotArray())longest=Math.Max(longest,key.AsGodotObject().Get("time").AsDouble());foreach(var raw in Document(owner).Get("component_events").AsGodotArray())longest=Math.Max(longest,raw.AsGodotDictionary()["time"].AsDouble());begin(owner);double duration=Math.Max(Math.Max(.05,value),longest);Document(owner).Set("duration",duration);owner.Set("playhead",Math.Min(owner.Get("playhead").AsDouble(),duration));commit(owner,"Animation duration");}
}
