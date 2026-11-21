using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ActorPropertyBatchOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorDefinitionOperations _definitions=new();private readonly ActorPropertyOperations _properties=new();private readonly ActorAnimationOperations _animation=new();private readonly Expression _equality=Equality();
    private static Expression Equality(){var value=new Expression();value.Parse("a == b",new[]{"a","b"});return value;}
    private bool Equal(Variant a,Variant b)=>_equality.Execute(new GArray{a,b}).AsBool();
    private static RefCounted Model(RefCounted owner)=>owner.Get("model").As<RefCounted>();
    private Resource? Definition(RefCounted owner,Resource actor)=>_definitions.get_definition(owner.Get("registry").As<RefCounted>(),actor.Get("type_id").AsStringName());
    private Variant DefinitionValue(RefCounted owner,Resource actor){var definition=Definition(owner,actor);return definition!=null?Variant.From(definition):default;}
    private static GArray Untyped(Godot.Collections.Array<Settings> values)=>Variant.From(values).AsGodotArray();
    public GArray targets(RefCounted owner,Resource primary,StringName key,Variant value)
    {
        var result=new GArray();var selected=Model(owner).Call("selected_actors").AsGodotArray();var candidates=selected.Contains(primary)?selected:new GArray{primary};foreach(var item in candidates){var actor=item.As<Resource>();var definition=Definition(owner,actor);var property=definition!=null?_definitions.find_property(definition,key):null;if(property!=null&&_properties.accepts(property,value))result.Add(actor);}return result;
    }
    public Godot.Collections.Array<Settings> capture(RefCounted owner,GArray actors,StringName key)
    {
        var result=new Godot.Collections.Array<Settings>();var model=Model(owner);foreach(var value in actors){var actor=value.As<Resource>();var values=actor.Get("values").AsGodotDictionary();var state=new Settings{["actor"]=actor,["key"]=key,["value"]=_data.copy_value(values.TryGetValue(key,out var original)?original:default),["tracks"]=model.Call("animation_snapshot",actor)};result.Add(state);if(actor.Get("type_id").AsString()=="audio"&&(key.ToString() is "audio" or "speed")){var clip=model.Call("clip_for_actor_id",actor.Get("id")).As<Resource>();state["timing"]=new Settings{["clip"]=clip,["duration"]=clip.Get("duration"),["offset"]=clip.Get("source_offset"),["speed"]=clip.Get("playback_speed"),["layer"]=clip.Get("layer")};}}return result;
    }
    public void restore(RefCounted owner,GArray states)=>RestoreModel(Model(owner),states,_data);
    internal static void RestoreModel(RefCounted model,GArray states,ActorDataOperations data)
    {
        foreach(var value in states){var state=value.AsGodotDictionary();var actor=state["actor"].As<Resource>();model.Get("_audio_preview_before").AsGodotDictionary().Remove(actor.Get("id"));if(state.TryGetValue("timing",out var captured)){var timing=captured.AsGodotDictionary();var clip=timing["clip"].As<Resource>();clip.Set("duration",timing["duration"]);clip.Set("source_offset",timing["offset"]);clip.Set("playback_speed",timing["speed"]);clip.Set("layer",timing["layer"]);}actor.Get("values").AsGodotDictionary()[state["key"]]=data.copy_value(state["value"]);actor.Get("animation_previews").AsGodotDictionary().Clear();model.Call("restore_animation",actor,state["tracks"]);}
    }
    public void edit(RefCounted owner,Resource primary,StringName key,Variant value)
    {
        var model=Model(owner);string type=primary.Get("type_id").AsString(),name=key.ToString();if(type=="powder"&&name=="powder_link_appearance"){GD.Load<GDScript>("res://scripts/actors/physics/powder/powder_material.gd").Call("link",model,owner.Call("targets",primary,key,value),value.AsBool());return;}if(type=="powder"&&name=="powder_material"){var original=_data.get_value(primary,key,default);var current=original.VariantType==Variant.Type.Object&&original.AsGodotObject() is Resource reference&&ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd")?_animation.resolve_reference(reference):null;var next=value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource chosen&&ActorDataOperations.ScriptIs(chosen,"res://scripts/actors/core/actor_object_reference.gd")?_animation.resolve_reference(chosen):null;int mode=next==null||current!=null&&Equal(_data.object_get_value(current,"material_id",""),_data.object_get_value(next,"material_id",""))?1:0;GD.Load<GDScript>("res://scripts/actors/physics/powder/powder_material.gd").Call("apply",model,owner.Call("targets",primary,key,value),value,mode);return;}if(type=="powder"&&name=="powder_advanced_material"){GD.Load<GDScript>("res://scripts/actors/physics/powder/powder_settings.gd").Call("switch_mode",model,owner.Call("targets",primary,key,value),value.AsBool());return;}if((type is "video" or "video_2d")&&(name is "video" or "linked_audio_actor")){model.Call("edit_property",primary,DefinitionValue(owner,primary),key,value);return;}var actors=targets(owner,primary,key,value);var before=capture(owner,actors,key);model.Set("property_batch_active",true);try{foreach(var item in actors){var actor=item.As<Resource>();model.Call("edit_property",actor,DefinitionValue(owner,actor),key,value);}}finally{model.Set("property_batch_active",false);}commit(owner,Untyped(before),Untyped(capture(owner,actors,key)),key);
    }
    public void preview(RefCounted owner,Resource primary,StringName key,Variant value)
    {
        var before=owner.Get("_before").AsGodotArray();if(before.Count==0){owner.Set("_key",key);owner.Set("_primary_original",_data.copy_value(_data.get_value(primary,key,default)));owner.Set("_before",capture(owner,targets(owner,primary,key,value),key));before=owner.Get("_before").AsGodotArray();}if(Equal(value,owner.Get("_primary_original"))){restore(owner,before);before.Clear();return;}foreach(var item in before){var actor=item.AsGodotDictionary()["actor"].As<Resource>();Model(owner).Call("preview_property",actor,DefinitionValue(owner,actor),key,value);}
    }
    public void finish(RefCounted owner,Resource primary,StringName key,Variant original,Variant value)
    {
        var before=owner.Get("_before").AsGodotArray();if(before.Count==0){if(!Equal(original,value))edit(owner,primary,key,value);return;}owner.Set("_before",new Godot.Collections.Array<Settings>());var model=Model(owner);model.Set("property_batch_active",true);try{foreach(var item in before){var state=item.AsGodotDictionary();var actor=state["actor"].As<Resource>();model.Call("commit_property_preview",actor,DefinitionValue(owner,actor),key,state["value"],value);}}finally{model.Set("property_batch_active",false);}var actors=new GArray();foreach(var item in before)actors.Add(item.AsGodotDictionary()["actor"]);commit(owner,before,Untyped(capture(owner,actors,key)),key);
    }
    public void commit(RefCounted owner,GArray before,GArray after,StringName key)
    {
        if(before.Count==0)return;var definition=Definition(owner,before[0].AsGodotDictionary()["actor"].As<Resource>());var property=definition!=null?_definitions.find_property(definition,key):null;string label=property!=null?property.Get("label").AsString():key.ToString();var history=Model(owner).Get("history").As<UndoRedo>();history.CreateAction((before.Count==1?"Change ":"Change Selected Actors: ")+label);var action=new ActorPropertyBatchRestoreAction(Model(owner),before,after);history.AddDoMethod(new Callable(action,nameof(ActorPropertyBatchRestoreAction.restore_after)));history.AddUndoMethod(new Callable(action,nameof(ActorPropertyBatchRestoreAction.restore_before)));history.AddDoReference(action);history.CommitAction();
    }
}
