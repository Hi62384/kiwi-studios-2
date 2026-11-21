using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TransformationSessionOperations : RefCounted
{
    private static Resource Document(RefCounted owner)=>owner.Get("document").As<Resource>();
    private static GArray Components(RefCounted owner)=>Document(owner).Get("components").AsGodotArray();
    private static GArray Array(RefCounted owner,string key)=>owner.Get(key).AsGodotArray();
    private static Settings Dict(RefCounted owner,string key)=>owner.Get(key).AsGodotDictionary();
    private static Resource? Component(RefCounted owner,string id)=>Document(owner).Call("component",id).As<Resource>();
    private static bool Contains(GArray values,string id){foreach(var value in values)if(value.AsString()==id)return true;return false;}
    private static void Assign(GArray target,IEnumerable<Variant> source){var copy=new List<Variant>(source);target.Clear();foreach(var value in copy)target.Add(value);}
    private static void Changed(RefCounted owner)=>owner.EmitSignal("changed");
    private static string NewId()=>ActorData.new_id();
    public Resource? primary(RefCounted owner){var selected=Array(owner,"selected");return selected.Count>0?Component(owner,selected[selected.Count-1].AsString()):null;}
    public Resource? active_state(RefCounted owner,Resource? item){item??=primary(owner);if(item==null)return null;string id=item.Get("id").AsString();var edits=Dict(owner,"edit_states");var state=item.Call("state_for_id",edits.TryGetValue(id,out var edited)?edited:item.Get("default_state_id")).As<Resource>();return state??item.Call("state_for_id",item.Get("default_state_id")).As<Resource>();}
    public void restore_view_state(RefCounted owner,Settings saved)
    {
        var selected=Array(owner,"selected");var edits=Dict(owner,"edit_states");selected.Clear();edits.Clear();if(saved.TryGetValue("selected",out var selection)){IEnumerable<string> ids=selection.VariantType==Variant.Type.PackedStringArray?selection.AsStringArray():selection.VariantType==Variant.Type.Array?Strings(selection.AsGodotArray()):System.Array.Empty<string>();foreach(string id in ids)if(Component(owner,id)!=null&&!Contains(selected,id))selected.Add(id);}if(saved.TryGetValue("states",out var states)&&states.VariantType==Variant.Type.Dictionary){var values=states.AsGodotDictionary();foreach(var raw in Components(owner)){var item=raw.As<Resource>();string id=item.Get("id").AsString();if(values.TryGetValue(id,out var state)&&state.VariantType==Variant.Type.String&&item.Call("state_for_id",state).AsGodotObject()!=null)edits[id]=state;}}double time=0;if(saved.TryGetValue("time",out var value)&&value.VariantType is Variant.Type.Float or Variant.Type.Int){time=value.AsDouble();if(!double.IsFinite(time))time=0;}owner.Set("playhead",Math.Clamp(time,0,Document(owner).Get("duration").AsDouble()));if(selected.Count==0&&Components(owner).Count>0)selected.Add(Components(owner)[0].AsGodotObject().Get("id"));
    }
    private static IEnumerable<string> Strings(GArray values){foreach(var value in values)if(value.VariantType==Variant.Type.String)yield return value.AsString();}
    public Settings snapshot(RefCounted owner)=>new() {["document"]=Document(owner).Call("snapshot"),["selected"]=Array(owner,"selected").Duplicate(),["states"]=Dict(owner,"edit_states").Duplicate(),["keys"]=Array(owner,"selected_keys").Duplicate(),["mask"]=owner.Get("pixel_mask"),["pixel_reference"]=Dict(owner,"pixel_reference").Duplicate()};
    public void restore(RefCounted owner,Settings state){owner.Set("document",state["document"].AsGodotObject().Call("snapshot"));Assign(Array(owner,"selected"),state["selected"].AsGodotArray());owner.Set("edit_states",state["states"].AsGodotDictionary().Duplicate());Assign(Array(owner,"selected_keys"),state["keys"].AsGodotArray());owner.Set("pixel_mask",state.TryGetValue("mask",out var mask)?mask:default);owner.Set("pixel_reference",state.TryGetValue("pixel_reference",out var reference)?reference.AsGodotDictionary().Duplicate():new Settings());Changed(owner);}
    public void begin(RefCounted owner){if(Dict(owner,"pending").Count==0)owner.Set("pending",snapshot(owner));}
    public void cancel(RefCounted owner){var pending=Dict(owner,"pending");if(pending.Count==0)return;owner.Set("pending",new Settings());restore(owner,pending);}
    public void commit(RefCounted owner,string label){var pending=Dict(owner,"pending");if(pending.Count==0)return;var undo=Array(owner,"undo_stack");undo.Add(new Settings {["before"]=pending,["after"]=snapshot(owner),["label"]=label});owner.Set("pending",new Settings());Array(owner,"redo_stack").Clear();while(undo.Count>40)undo.RemoveAt(0);while(undo.Count>1&&history_bytes(owner)>268435456)undo.RemoveAt(0);owner.Set("revision",owner.Get("revision").AsInt64()+1);owner.Set("dirty",true);Changed(owner);}
    public long history_bytes(RefCounted owner)
    {
        var seen=new HashSet<ulong>();long bytes=0;void Texture(Variant value,bool retained){if(value.VariantType!=Variant.Type.Object||value.AsGodotObject() is not Texture2D texture||!seen.Add(texture.GetInstanceId()))return;if(retained)bytes+=(long)texture.GetWidth()*texture.GetHeight()*4;}
        void Inspect(Resource document,bool retained){foreach(var raw in document.Get("components").AsGodotArray())foreach(var state in raw.AsGodotObject().Get("states").AsGodotArray()){var art=state.AsGodotObject().Get("artwork").AsGodotObject();Texture(art.Get("texture"),retained);Texture(art.Get("paint_base"),retained);}foreach(var raw in document.Get("component_events").AsGodotArray())if(raw.AsGodotDictionary().TryGetValue("mask",out var mask))Texture(mask,retained);}
        Inspect(Document(owner),false);var current=owner.Get("pixel_mask").As<Image>();if(current!=null)seen.Add(current.GetInstanceId());foreach(var raw in Array(owner,"undo_stack")){var entry=raw.AsGodotDictionary();foreach(string which in new[]{"before","after"}){var state=entry[which].AsGodotDictionary();Inspect(state["document"].As<Resource>(),true);if(state.TryGetValue("mask",out var value)&&value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Image mask&&seen.Add(mask.GetInstanceId()))bytes+=(long)mask.GetWidth()*mask.GetHeight()*4;}}return bytes;
    }
    public void undo(RefCounted owner){if(Dict(owner,"pending").Count>0){cancel(owner);return;}Transfer(owner,"undo_stack","redo_stack","before");}
    public void redo(RefCounted owner)=>Transfer(owner,"redo_stack","undo_stack","after");
    private void Transfer(RefCounted owner,string source,string target,string which){var stack=Array(owner,source);if(stack.Count==0)return;var entry=stack[stack.Count-1];stack.RemoveAt(stack.Count-1);Array(owner,target).Add(entry);owner.Set("dirty",true);owner.Set("revision",owner.Get("revision").AsInt64()+1);restore(owner,entry.AsGodotDictionary()[which].AsGodotDictionary());}
    public void select(RefCounted owner,string id,bool additive){var selected=Array(owner,"selected");if(!additive)selected.Clear();if(id.Length>0){if(Contains(selected,id)){for(int index=selected.Count-1;index>=0;index--)if(selected[index].AsString()==id)selected.RemoveAt(index);}else selected.Add(id);}Changed(owner);}
    public Resource? key_at(Resource item,double at){foreach(var raw in item.Get("keys").AsGodotArray()){var key=raw.As<Resource>();if(Math.Abs(key.Get("time").AsDouble()-at)<.00001)return key;}return null;}
    public Settings sampled(Resource item,double time)
    {
        var keys=item.Call("sorted_keys").AsGodotArray();if(keys.Count==0){var state=item.Call("state_for_id",item.Get("default_state_id"));return new Settings {["a"]=state,["b"]=state,["t"]=0.0,["key"]=default(Variant)};}var left=keys[0].As<Resource>();var right=left;foreach(var raw in keys){var key=raw.As<Resource>();double at=key.Get("time").AsDouble();if(at<=time){left=key;right=key;}else{right=key;break;}}if(time<keys[0].AsGodotObject().Get("time").AsDouble()){left=keys[0].As<Resource>();right=left;}double weight=right!=left?Math.Clamp((time-left.Get("time").AsDouble())/Math.Max(.000001,right.Get("time").AsDouble()-left.Get("time").AsDouble()),0,1):0;bool step=left.Get("mode").AsString()=="Step";return new Settings {["a"]=item.Call("state_for_id",left.Get("state_id")),["b"]=item.Call("state_for_id",right.Get("state_id")),["t"]=step?Variant.From(0.0):left.Call("progress",weight),["key"]=left};
    }
}
