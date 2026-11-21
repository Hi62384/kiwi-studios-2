using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogCloudPresetsOperations:RefCounted
{
    private readonly FogFieldOperations _field=new();private readonly FogAppearanceOperations _appearance=new();private readonly ActorDefinitionOperations _definitions=new();private readonly ActorDataOperations _data=new();private readonly ActorAnimationOperations _animation=new();
    private GArray Titles=>GD.Load<GDScript>("res://scripts/actors/fog/fog_cloud_presets.gd").GetScriptConstantMap()["TITLES"].AsGodotArray();
    public Settings configuration(int index,Variant original)
    {
        index=Math.Clamp(index,0,19);var field=_definitions.create_object(_field.definition());var appearance=_definitions.create_object(_appearance.definition());var f=field.Get("values").AsGodotDictionary();var a=appearance.Get("values").AsGodotDictionary();int kind=new[]{0,0,1,2,3,0,0,0,4,4,4,4,4,4,5,5,5,5,1,5}[index];f.Merge(new Settings{["mode"]=8,["cloud_type"]=kind,["resolution"]=1,["cloud_coverage"]=.65,["cloud_base"]=.04,["cloud_thickness"]=.92,["seed"]=31},true);a.Merge(new Settings{["title"]=Titles[index],["cloud_lighting"]=kind<4,["cloud_shadow_strength"]=1.0,["silver_lining"]=kind<4?.5:0,["cloud_lod"]=kind<4},true);double optical=new[]{.18,.4,.12,.045,.65,.2,.18,.15,.03,.08,.06,.045,.25,.05,.002,.008,.018,.012,.1,.007}[index];if(index==0)f["cloud_coverage"]=.45;if(index==1){f["cloud_detail"]=.65;f["cloud_coverage"]=.85;}if(kind==1){f["cloud_base"]=.3;f["cloud_thickness"]=.4;}if(kind==2){f["cloud_base"]=.35;f["cloud_thickness"]=.3;f["cloud_erosion"]=.1;f["cloud_size"]=.3;}if(kind==3){f["cloud_coverage"]=.85;f["cloud_detail"]=.7;a["gradient"]=1;a["color"]=new Color("374554");a["secondary"]=new Color("c0c8d2");}if(index is 5 or 6 or 7 or 13 or 19){a["render_style"]=index switch{5=>1,6=>2,7=>4,13=>3,_=>2};a["gradient"]=1;a["color"]=new Color("86a9cd");a["secondary"]=new Color("fff3db");f["cloud_erosion"]=.05;}if(index==7){a["color"]=new Color("9d77d0");a["secondary"]=new Color("e9a0cd");a["emission"]=new Color(.05f,.01f,.1f);}if(kind==4){a["color"]=new Color("cedde3");f["cloud_coverage"]=.85;f["cloud_ground_falloff"]=new[]{3.0,1,6,4,2,3}[index-8];}if(index==10){f["cloud_size"]=2.0;f["cloud_detail"]=.1;}if(index==11){a["color"]=new Color("9aac9c");f["cloud_coverage"]=.6;}if(index==12){a["color"]=new Color("59677c");a["absorption"]=.8;}if(index==16)a["color"]=new Color("be9b73");if(index==17)a["color"]=new Color("a2c6c9");if(kind==5){if(index is not (16 or 17))a["color"]=new Color("b6cce1");f["cloud_ground_falloff"]=1000.0;f["cloud_base"]=0.0;f["cloud_thickness"]=1.0;}Resource? previous=null;if(original.VariantType==Variant.Type.Object&&original.AsGodotObject() is Resource r){if(ActorDataOperations.ScriptIs(r,"res://scripts/actors/core/actor_object_reference.gd"))previous=_animation.resolve_reference(r);else if(ActorDataOperations.ScriptIs(r,"res://scripts/actors/core/actor_object_data.gd"))previous=r;}if(previous!=null){var values=previous.Get("values").AsGodotDictionary();f["mask"]=values.GetValueOrDefault("mode",0).AsInt32()==8?values.GetValueOrDefault("mask",default(Variant)):original;}return new Settings{[new StringName("field")]=_data.from_object(field),[new StringName("appearance")]=_data.from_object(appearance),[new StringName("density")]=optical};
    }
    public void apply(RefCounted model,Resource actor,int index)
    {
        var values=actor.Get("values").AsGodotDictionary();var next=configuration(index,values.GetValueOrDefault("field",default(Variant)));var before=new Settings();foreach(var key in next.Keys)before[key]=_data.copy_value(values.GetValueOrDefault(key,default(Variant)));var action=new FogPropertyHistoryAction(model,actor,before,next,false);var history=model.Get("history").As<UndoRedo>();history.CreateAction("Atmosphere: "+Titles[Math.Clamp(index,0,19)].AsString());history.AddDoMethod(new Callable(action,"restore_after"));history.AddUndoMethod(new Callable(action,"restore_before"));history.AddDoReference(action);history.CommitAction();
    }
}
public partial class FogPropertyHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly Resource? _target;private readonly Settings? _before,_after;private readonly bool _object;
    public FogPropertyHistoryAction(){}
    public FogPropertyHistoryAction(RefCounted model,Resource target,Settings before,Settings after,bool objectTarget){_model=GodotObject.WeakRef(model);_target=target;_before=before;_after=after;_object=objectTarget;}
    private void Restore(Settings? values){if(_model==null||_target==null||values==null)return;using var reference=_model.GetRef();if(reference.AsGodotObject() is RefCounted model&&GodotObject.IsInstanceValid(model))foreach(var entry in values)model.Call(_object?"_set_object_property":"_set_property",_target,new StringName(entry.Key.AsString()),entry.Value);}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
}
