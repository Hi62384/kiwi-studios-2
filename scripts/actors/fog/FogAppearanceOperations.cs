using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogAppearanceOperations:RefCounted
{
    private readonly ActorPropertyOperations _properties=new();private readonly ActorDefinitionOperations _definitions=new();private readonly ActorDataOperations _data=new();private readonly FogFieldOperations _field=new();
    private GDScript Bridge=>GD.Load<GDScript>("res://scripts/actors/fog/fog_appearance.gd");
    private Resource Add(Resource d,string key,string title,Variant value){var p=_properties.create(new StringName(key),title,value,false);d.Get("properties").AsGodotArray().Add(p);return p;}
    public Resource definition()
    {
        var d=new ActorObjectDefinition();d.Set("type_id",new StringName("fog_appearance"));d.Set("display_name","Fog Appearance");foreach(var item in Bridge.GetScriptConstantMap()["FIELD_ROWS"].AsGodotArray()){var row=item.AsGodotArray();var p=_properties.create(new StringName(row[0].AsString()),row[1].AsString(),row[2],true);p.Get("options").AsGodotDictionary().Merge(row[4].AsGodotDictionary());p.Get("options").AsGodotDictionary()["group"]=row[3];d.Get("properties").AsGodotArray().Add(p);}foreach(string key in new[]{"color_texture","density_texture","mask_texture","detail_texture"}){var p=Add(d,key,key.Capitalize(),default);p.Set("object_type",new StringName("image"));p.Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Textures",["accepted_object_types"]=new GArray{"image","noise_image"}});}foreach(string key in new[]{"density_volume","color_volume"})Add(d,key,key.Capitalize(),"").Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Textures",["file_picker"]=true,["extensions"]=new GArray{"tres","res"},["native_resource_types"]=new GArray{"Texture3D"},["file_resource_mode"]="uneditable"});for(int i=0;i<4;i++){var p=Add(d,"layer_"+i,"Appearance influence "+(i+1),default);p.Set("object_type",new StringName("fog_field"));p.Get("options").AsGodotDictionary()["group"]="Layers";}return d;
    }
    public Resource preset(int index)
    {
        var data=_definitions.create_object(definition());index=Math.Clamp(index,0,5);var values=data.Get("values").AsGodotDictionary();values["title"]=Bridge.GetScriptConstantMap()["PRESETS"].AsGodotArray()[index];values["color"]=new Color(new[]{"edf3ff","bbc3c9","c5d8e9","ad8d6d","768bff","3d4b58"}[index]);values["density_multiplier"]=new[]{.12,2,.2,.45,.65,.8}[index];if(index==4){values["gradient"]=1;values["secondary"]=new Color("bc64e8");}var field=_definitions.create_object(_field.definition());field.Get("values").AsGodotDictionary()["mode"]=4;field.Get("values").AsGodotDictionary()["strength"]=new[]{.15,.45,.2,.6,.3,.7}[index];values["layer_0"]=_data.from_object(field);if(index==2){var height=_definitions.create_object(_field.definition());height.Get("values").AsGodotDictionary()["mode"]=1;height.Get("values").AsGodotDictionary()["invert"]=true;values["layer_1"]=_data.from_object(height);}return data;
    }
    public double optical_density(double field,Settings values)
    {
        double N(string key,double fallback=0)=>values.GetValueOrDefault(key,fallback).AsDouble();double density=Math.Max(0,field+N("offset")-N("threshold"));density=Math.Pow(density,Math.Clamp(N("contrast",1),.01,16))*Math.Max(0,N("density_multiplier",1));density*=Math.Clamp(N("opacity",1),0,1)*(1+Math.Max(0,N("absorption")));return double.IsFinite(density)?Math.Clamp(density,0,N("maximum",64)):0;
    }
}
