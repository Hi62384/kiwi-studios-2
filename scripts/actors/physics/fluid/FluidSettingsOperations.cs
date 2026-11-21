using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class FluidSettingsOperations:RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback)=>values.TryGetValue(key,out var result)?result:fallback;
    public Settings effective(Settings values){var result=values.Duplicate();int quality=Math.Clamp(Get(values,"fluid_quality",1).AsInt32(),0,2);double spacing=Math.Max(.025,Get(values,"fluid_spacing",.22).AsDouble())*new[]{1.3,1,.75}[quality];result["spacing"]=spacing;result["iterations"]=Math.Clamp(Get(values,"fluid_iterations",3).AsInt32()+new[]{-1,0,2}[quality],1,10);result["substeps"]=Math.Clamp(Get(values,"fluid_substeps",1).AsInt32()+new[]{0,1,2}[quality],1,6);result["cell"]=spacing*new[]{1.15,.85,.65}[quality]*Get(values,"fluid_surface_scale",1.0).AsDouble();result["budget"]=Math.Clamp(Get(values,"fluid_budget",1024).AsInt32(),16,4096);return result;}
    public void preset(RefCounted model,Resource actor,int index){var before=actor.Get("values").AsGodotDictionary().Duplicate(true);var after=before.Duplicate(true);after.Merge(GD.Load<GDScript>("res://scripts/actors/physics/fluid/fluid_settings.gd").GetScriptConstantMap()["PRESETS"].AsGodotArray()[Math.Clamp(index,0,4)].AsGodotDictionary(),true);after[new StringName("fluid_preset")]=index;var history=model.Get("history").As<UndoRedo>();var action=new FluidSettingsHistoryAction(model,actor,before,after);history.CreateAction("Fluid preset");history.AddDoMethod(new Callable(action,nameof(FluidSettingsHistoryAction.restore_after)));history.AddUndoMethod(new Callable(action,nameof(FluidSettingsHistoryAction.restore_before)));history.AddDoReference(action);history.CommitAction();}
    public void assign(RefCounted model,Resource actor,Settings values){actor.Set("values",values.Duplicate(true));actor.EmitChanged();model.EmitSignal("changed");}
}
