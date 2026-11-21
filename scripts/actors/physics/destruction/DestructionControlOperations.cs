using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class DestructionControlOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorAnimationOperations _animation=new();private readonly ActorPropertyOperations _properties=new();private readonly DestructionDefinitionOperations _definition=new();private readonly DestructionAuthoringOperations _authoring=new();
    private static Control Host(VBoxContainer owner)=>owner.Get("host").As<Control>();private static Resource Actor(VBoxContainer owner)=>owner.Get("actor").As<Resource>();private static RefCounted Model(VBoxContainer owner)=>Host(owner).Get("model").As<RefCounted>();private Settings Operations(VBoxContainer owner)=>_data.get_value(Actor(owner),new StringName("destruction_operations"),new Settings()).AsGodotDictionary();private static GArray Keys(Settings values){var result=new GArray();foreach(var key in values.Keys)result.Add(key);return result;}private static double Time(Resource actor){double time=actor.Get("animation_time").AsDouble();return double.IsNaN(time)?0:time;}
    public void setup(VBoxContainer owner,Control inspector,Resource actor){owner.Set("host",inspector);owner.Set("actor",actor);owner.Name="DestructionOperations";build(owner);var updater=new Callable(owner,"sync");owner.Set("_sync_callback",updater);inspector.Get("_updaters").AsGodotArray().Add(updater);}
    public void sync(VBoxContainer owner){if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree()||owner.Get("queued").AsBool())return;if(GD.Hash(Keys(Operations(owner)))!=owner.Get("layout").AsInt64()){owner.Set("queued",true);owner.CallDeferred("build");}}
    public void exit_tree(VBoxContainer owner){var host=Host(owner);if(!GodotObject.IsInstanceValid(host))return;host.Get("_updaters").AsGodotArray().Remove(owner.Get("_sync_callback"));foreach(var callback in owner.Get("callbacks").AsGodotArray())host.Get("_updaters").AsGodotArray().Remove(callback);}
    public void commit_drag(VBoxContainer owner,string id,string key,Variant value,Settings before){var actor=Actor(owner);var path=new[]{"destruction_operations",id,key};if(_data.animation_track(actor,path)!=null){Model(owner).Call("commit_animation_value",actor,path,value);return;}actor.Get("values").AsGodotDictionary()["destruction_operations"]=_data.copy_value(before);change(owner,id,key,value,false);}
    public void cancel_drag(VBoxContainer owner,string id,string key,Settings before){var actor=Actor(owner);actor.Get("animation_previews").AsGodotDictionary().Remove(string.Join(" / ",new[]{"destruction_operations",id,key}));actor.Get("values").AsGodotDictionary()["destruction_operations"]=_data.copy_value(before);actor.EmitChanged();Model(owner).EmitSignal("changed");}
    public void change(VBoxContainer owner,string id,string key,Variant value,bool preview){var actor=Actor(owner);var path=new[]{"destruction_operations",id,key};if(_data.animation_track(actor,path)!=null){Model(owner).Call(preview?"preview_animation_value":"commit_animation_value",actor,path,value);return;}var operations=Operations(owner).Duplicate(true);if(!operations.ContainsKey(id))return;operations[id].AsGodotDictionary()[key]=value;if(preview){actor.Get("values").AsGodotDictionary()["destruction_operations"]=operations;Model(owner).EmitSignal("changed");}else _definition.edit(Model(owner),actor,operations,"Edit destruction");if(key=="physical")owner.CallDeferred("build");}
    private void Bind(VBoxContainer owner,SpinBox number,string id,string key,Func<double,Variant> value)
    {
        Settings before=new();number.Connect("interaction_started",Callable.From(()=>before=_data.copy_value(Operations(owner)).AsGodotDictionary()));number.Connect("preview_changed",Callable.From<double>(v=>change(owner,id,key,value(v),true)));number.Connect("drag_committed",Callable.From<double>(v=>commit_drag(owner,id,key,value(v),before)));number.Connect("drag_cancelled",Callable.From(()=>cancel_drag(owner,id,key,before)));number.ValueChanged+=v=>change(owner,id,key,value(v),false);
    }
    private SpinBox Number(string name,bool lesser,double step,double value){var number=new DragNumber();number.Name=name;number.AllowGreater=true;number.AllowLesser=lesser;number.Step=step;number.SetValueNoSignal(value);return number;}
    private void UpdateNumber(VBoxContainer owner,SpinBox number,string key,int axis=-1)
    {
        if(!GodotObject.IsInstanceValid(number)||number.Get("dragging").AsBool())return;var actor=Actor(owner);var path=new[]{"destruction_operations",owner.Get("selected").AsString(),key};var value=_animation.sampled_value(actor,path,Time(actor),_animation.value_at_path(actor,path));if(axis>=0){if(value.VariantType==Variant.Type.Vector3)number.SetValueNoSignal(value.AsVector3()[axis]);}else if(value.VariantType is Variant.Type.Float or Variant.Type.Int)number.SetValueNoSignal(value.AsDouble());
    }
}
