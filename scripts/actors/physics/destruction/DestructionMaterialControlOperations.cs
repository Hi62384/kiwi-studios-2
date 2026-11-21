using Godot;
using System;
using GArray=Godot.Collections.Array;
public partial class DestructionMaterialControlOperations:RefCounted
{
    private readonly DestructionMaterialOperations _materials=new();private readonly ActorDataOperations _data=new();
    public void setup(HBoxContainer owner,Control host,Resource actor){owner.Name="DamageMaterialPresets";var choice=new OptionButton{Name="DamageMaterialPreset",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};var names=GD.Load<GDScript>("res://scripts/actors/physics/destruction/destruction_material.gd").GetScriptConstantMap()["NAMES"].AsGodotArray();foreach(var title in names)choice.AddItem(title.AsString());var current=_materials.resolve(actor.Get("values").AsGodotDictionary(),Vector3.Zero);if(current!=null){string name=_data.object_get_value(current,new StringName("material_name"),"").AsString();int selected=0;for(int i=0;i<names.Count;i++)if(names[i].AsString()==name){selected=i;break;}choice.Select(selected);}owner.AddChild(choice);var apply=new Button{Name="ApplyDamageMaterial",Text="✓",TooltipText="Apply selected physical material preset",CustomMinimumSize=new Vector2(30,0)};owner.AddChild(apply);apply.Pressed+=()=>{var definition=host.Get("registry").AsGodotObject().Call("get_definition",actor.Get("type_id"));host.Call("_edit_property",actor,definition,new StringName("destruction_material"),_data.from_object(_materials.preset(choice.Selected)));host.Call("_queue_rebuild_selected");};}
}
